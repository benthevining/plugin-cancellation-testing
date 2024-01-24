
# Idea: a function like mtm_auto_cancellation_test that would discover what files are in a directory
# make INPUT_AUDIO a variadic argument and remove SIDECHAIN_INPUT INPUT_AUDIO not required if
# INPUT_MIDI is given

include_guard (GLOBAL)

find_program (PLUGALYZER_PROGRAM plugalyzer DOC "Plugalyzer executable")

define_property (
	DIRECTORY
	PROPERTY CANCELLATION_REGEN_TARGET
	INHERITED
	BRIEF_DOCS "Name of custom target to drive reference file regeneration"
	FULL_DOCS
		"Reference audio files for all cancellation tests in this directory can be regenerated by the custom target named in this property"
)

#[[
	add_plugin_cancellation_test (
		<pluginTarget>
		REFERENCE_AUDIO <audioFile>
		[INPUT_AUDIO <audioFile>...]
		[INPUT_MIDI <midiFile>]
		[RMS_THRESH <thresh> | EXACT]
		[STATE_FILE <jsonFile>]
		[PARAMS <name>:<value>[:n] <name>:<value>[:n] ...]
		[BLOCKSIZE <size>]
		[OUTPUT_DIR <directory>]
		[TEST_PREFIX <prefix>]
		[REGEN_TARGET <target>]
		[TEST_NAMES_OUT <variable>]
	)

	Adds an audio cancellation test. The purpose of a cancellation test is to verify that a plugin, given the same
	audio input and parameter values, will produce the same output as a known "good" version (ie, the last tagged
	release, etc). This function registers tests that perform the following steps:
	- Render audio using the given input audio, MIDI, and parameter settings. This is done using Plugalyzer.
	- Calculate the difference between the rendered audio and the reference audio. In this implementation, we consider
	the rendered test signal to be the reference signal + noise, so we attempt to measure the amount of noise by
	subtracting the reference audio from the rendered audio and taking the RMS of the result.
	- Fail the cancellation test if the determined noise level is higher than RMS_THRESH

	The determined noise level is also output in a manner known to CTest, so that it will, by default, be included
	in CDash dashboards as a numeric measurement for historical tracking and analysis. The rendered and reference
	audio files will be uploaded to CDash as well, for archival purposes.

	These tests require Plugalyzer to be found in the PATH, CMAKE_PREFIX_PATH, or CMAKE_PROGRAM_PATH. Its path can
	also be set explicitly using the PLUGALYZER_PROGRAM variable. It can be built from source; the code is available
	from https://github.com/CrushedPixel/Plugalyzer.

	You must specify either INPUT_AUDIO or INPUT_MIDI, or optionally both. If you specify multiple audio inputs, they
	will be used as additional input buses (ie sidechains). The first audio input file named will be the main input
	bus. If you specify no input audio and only input MIDI, it is implied that you are testing a VST instrument.

	RMS_THRESH determines how strict the test is; a value of 0 will require that the rendered audio is exactly the same
	as the reference audio with no deviation, and a value of 1 would allow a completely different audio output to
	"pass" the cancellation test. RMS threshold values may require tuning on a per-cancellation-test basis over time.
	EXACT is a shorthand for passing RMS_THRESH 0, and it is an error to specify both EXACT and an RMS_THRESH value.

	STATE_FILE is a JSON file containing parameter values, and can even describe parameter automations; see
	https://github.com/CrushedPixel/Plugalyzer for more details about the file format. Non-automated parameter values
	can also be set individually using the PARAMS keyword. For PARAMS, you can specify the parameter name or index.

	OUTPUT_DIR defines where the generated audio files will be written. The files will actually be generated in a
	build-configuration-specific subdirectory beneath OUTPUT_DIR. Defaults to ${CMAKE_CURRENT_BINARY_DIR}/cancellation-generated.

	TEST_PREFIX defines a prefix for the test names, and defaults to <pluginTarget>.Cancellation.<ReferenceFileName>

	REGEN_TARGET can be the name of a regeneration target (later added with add_cancellation_regeneration_target())
	that will drive regeneration of the reference audio file using the supplied inputs. If not specified, the value of
	the CANCELLATION_REGEN_TARGET directory property will be used, if set.

	TEST_NAMES_OUT can name a variable that will be populated in the calling scope with the names of the generated tests.
	This will be a list of 2 values, since each cancellation test is implemented using a render command and a diff command.

	Relative paths for all input variables are evaluated relative to CMAKE_CURRENT_SOURCE_DIR, except for OUTPUT_DIR,
	which is evaluated relative to CMAKE_CURRENT_BINARY_DIR.
]]
function (add_plugin_cancellation_test pluginTarget)

	list (APPEND CMAKE_MESSAGE_INDENT "  - ${CMAKE_CURRENT_FUNCTION}: ")

	if (NOT TARGET "${pluginTarget}")
		message (FATAL_ERROR "Plugin target '${pluginTarget}' does not exist!")
	endif ()

	# argument parsing & validating

	set (options
		EXACT
	)

	set (
		oneVal
		BLOCKSIZE
		INPUT_MIDI
		OUTPUT_DIR
		REFERENCE_AUDIO
		REGEN_TARGET
		RMS_THRESH
		SIDECHAIN_INPUT
		STATE_FILE
		TEST_PREFIX
		TEST_NAMES_OUT
	)

	set (
		multiVal
		INPUT_AUDIO
		PARAMS
	)

	cmake_parse_arguments (MTM_ARG "${options}" "${oneVal}" "${multiVal}" ${ARGN})

	if (NOT (MTM_ARG_INPUT_AUDIO OR MTM_ARG_INPUT_MIDI))
		message (FATAL_ERROR "You must specify either INPUT_AUDIO or INPUT_MIDI")
	endif ()

	if (NOT MTM_ARG_REFERENCE_AUDIO)
		message (FATAL_ERROR "Missing required argument REFERENCE_AUDIO")
	endif ()

	if(MTM_ARG_RMS_THRESH AND MTM_ARG_EXACT)
		message (FATAL_ERROR "RMS_THRESH and EXACT cannot both be specified")
	endif()

	if (NOT PLUGALYZER_PROGRAM)
		return ()
	endif ()

	# dummy set up test to create output directory

	if(MTM_ARG_OUTPUT_DIR)
		cmake_path (ABSOLUTE_PATH MTM_ARG_OUTPUT_DIR BASE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}")
	else()
		set (MTM_ARG_OUTPUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/cancellation-generated")
	endif()

	cmake_path (ABSOLUTE_PATH MTM_ARG_REFERENCE_AUDIO BASE_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}")

	cmake_path (GET MTM_ARG_REFERENCE_AUDIO STEM filename)

	if (NOT MTM_ARG_TEST_PREFIX)
		set (MTM_ARG_TEST_PREFIX "${pluginTarget}.Cancellation.${filename}.")
	endif ()

	set (base_dir "${MTM_ARG_OUTPUT_DIR}/$<CONFIG>")

	# the setup test is named for the output directory and does not include the test prefix so
	# that multiple cancellation tests using the same output directory can share one setup test
	string (MD5 base_dir_hash "${base_dir}")
	set (setup_test "Cancellation.Prepare.${base_dir_hash}")

	if(NOT TEST "${setup_test}")
		add_test (
			NAME "${setup_test}"
			COMMAND "${CMAKE_COMMAND}" -E make_directory "${base_dir}"
		)

		set_tests_properties ("${setup_test}" PROPERTIES FIXTURES_SETUP "${setup_test}")
		set_property (TEST "${setup_test}" APPEND PROPERTY LABELS Cancellation)
	endif()

	# create render test

	if (MTM_ARG_INPUT_MIDI)
		cmake_path (ABSOLUTE_PATH MTM_ARG_INPUT_MIDI BASE_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}")
		set (midi_input_arg "--midiInput=${MTM_ARG_INPUT_MIDI}")
	else ()
		unset (midi_input_arg)
	endif ()

	if (MTM_ARG_STATE_FILE)
		cmake_path (ABSOLUTE_PATH MTM_ARG_STATE_FILE BASE_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}")
		set (param_file_arg "--paramFile=${MTM_ARG_STATE_FILE}")
	else ()
		unset (param_file_arg)
	endif ()

	if (MTM_ARG_BLOCKSIZE)
		set (blocksize_arg "--blockSize=${MTM_ARG_BLOCKSIZE}")
	else ()
		unset (blocksize_arg)
	endif ()

	unset (input_audio_args)
	unset (input_audio_files)

	foreach(input IN LISTS MTM_ARG_INPUT_AUDIO)
		cmake_path (ABSOLUTE_PATH input BASE_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}")
		list (APPEND input_audio_args "--input=${input}")
		list (APPEND input_audio_files)
	endforeach()

	unset (explicit_param_args)

	foreach (param_arg IN LISTS MTM_ARG_PARAMS)
		list (APPEND explicit_param_args "--param=${param_arg}")
	endforeach ()

	cmake_path (GET MTM_ARG_REFERENCE_AUDIO EXTENSION extension)

	set (generated_audio "${base_dir}/${filename}${extension}")

	get_target_property (plugin_artefact "${pluginTarget}" JUCE_PLUGIN_ARTEFACT_FILE)

	set (process_test "${MTM_ARG_TEST_PREFIX}Render")

	add_test (
		NAME "${process_test}"
		COMMAND
			"${PLUGALYZER_PROGRAM}" process
			"--plugin=${plugin_artefact}"
			${input_audio_args} ${midi_input_arg}
			"--output=${generated_audio}" --overwrite
			${blocksize_arg} ${explicit_param_args} ${param_file_arg}
	)

	set_tests_properties (
		"${process_test}"
		PROPERTIES
			FIXTURES_REQUIRED "${setup_test}"
			REQUIRED_FILES "${plugin_artefact}"
			FIXTURES_SETUP "${process_test}"
	)

	set_property (
		TEST "${process_test}" APPEND 
		PROPERTY REQUIRED_FILES
		${MTM_ARG_INPUT_MIDI} ${MTM_ARG_STATE_FILE} ${input_audio_files}
	)

	# create diff test

	set (diff_test "${MTM_ARG_TEST_PREFIX}Diff")

	if (NOT MTM_ARG_RMS_THRESH)
		if(MTM_ARG_EXACT)
			set (MTM_ARG_RMS_THRESH 0.0)
		else()
			set (MTM_ARG_RMS_THRESH 0.005)
		endif()
	endif ()

	add_test (NAME "${diff_test}"
			  COMMAND cancellation::audio_diff
					  "${MTM_ARG_REFERENCE_AUDIO}" "${generated_audio}" "${MTM_ARG_RMS_THRESH}"
	)

	set_tests_properties (
		"${diff_test}"
		PROPERTIES
			FIXTURES_REQUIRED "${process_test}"
			REQUIRED_FILES "${MTM_ARG_REFERENCE_AUDIO};${generated_audio}"
			ATTACHED_FILES "${MTM_ARG_REFERENCE_AUDIO};${generated_audio}"
	)

	set_property (TEST "${process_test}" "${diff_test}" APPEND PROPERTY LABELS Cancellation)

	if(MTM_ARG_TEST_NAMES_OUT)
		set ("${MTM_ARG_TEST_NAMES_OUT}" "${process_test};${diff_test}" PARENT_SCOPE)
	endif()

	set_property (DIRECTORY APPEND PROPERTY ADDITIONAL_CLEAN_FILES "${generated_audio}")

	message (VERBOSE "Added plugin cancellation test ${MTM_ARG_TEST_PREFIX}")

	# create regen command

	if (NOT MTM_ARG_REGEN_TARGET)
		get_directory_property (MTM_ARG_REGEN_TARGET CANCELLATION_REGEN_TARGET)

		if (NOT MTM_ARG_REGEN_TARGET)
			return ()
		endif ()
	endif ()

	set (update_reference_output "${MTM_ARG_TEST_PREFIX}${filename}_regenerate")

	add_custom_command (
		OUTPUT "${update_reference_output}"
		COMMAND
			"${PLUGALYZER_PROGRAM}" process
			"--plugin=${plugin_artefact}"
			${input_audio_args} ${midi_input_arg}
			"--output=${MTM_ARG_REFERENCE_AUDIO}" --overwrite
			${blocksize_arg} ${explicit_param_args} ${param_file_arg}
		DEPENDS "${pluginTarget}" ${input_audio_files} ${MTM_ARG_INPUT_MIDI} ${MTM_ARG_STATE_FILE}
		COMMENT "Regenerating reference audio file '${filename}' for plugin cancellation test ${MTM_ARG_TEST_PREFIX}..."
		VERBATIM COMMAND_EXPAND_LISTS
	)

	set_source_files_properties ("${update_reference_output}" PROPERTIES SYMBOLIC ON)

	set (property_name "${MTM_ARG_REGEN_TARGET}_SymbolicRegenOutputs")

	# to silence warnings about writing to undefined properties
	define_property (
		DIRECTORY
		PROPERTY "${property_name}"
		FULL_DOCS 
			"List of symbolic outputs used to create reference file regeneration custom target later in this directory. For internal usage."
	)

	set_property (
		DIRECTORY APPEND PROPERTY "${property_name}" "${update_reference_output}"
	)

	message (VERBOSE 
		"Added reference file regeneration command for plugin cancellation test ${MTM_ARG_TEST_PREFIX}"
		" (regeneration target name: ${MTM_ARG_REGEN_TARGET})"
	)

endfunction ()

#[[
	add_cancellation_regeneration_target (<regenerationTarget>)

	Adds a custom target that, when built, will regenerate a set of reference audio files for cancellation tests.

	When you release a new version or tag of your plugin, manually run this target to update the reference files in your
	source tree. You should then rerun your cancellation tests with the new reference files to verify that everything is
	still working correctly, and then commit the changed reference files into your source control.

	<regenerationTarget> should be the same name you passed to the REGEN_TARGET argument of add_plugin_cancellation_test()
	(or set the CANCELLATION_REGEN_TARGET directory property to before calling that function). This function must be called
	in the same directory as the add_plugin_cancellation_test() calls for the reference files this regeneration target
	needs to regenerate.
]]
function (add_cancellation_regeneration_target regenerationTarget)

	if (NOT PLUGALYZER_PROGRAM)
		return ()
	endif ()

	list (APPEND CMAKE_MESSAGE_INDENT "  - ${CMAKE_CURRENT_FUNCTION}: ")

	get_directory_property (outputs "${regenerationTarget}_SymbolicRegenOutputs")

	if (NOT outputs)
		message (
			WARNING
				"No reference file outputs found for regeneration target ${regenerationTarget}."
				" Make sure you've called mtm_add_plugin_cancellation_test() first, and in the same directory as ${CMAKE_CURRENT_FUNCTION}."
		)
		return ()
	endif ()

	add_custom_target (
		"${regenerationTarget}"
		DEPENDS ${outputs}
		COMMENT "Regenerating cancellation test reference audio files..."
		VERBATIM
	)

	message (VERBOSE "Added reference file regeneration target ${regenerationTarget}")

endfunction ()
