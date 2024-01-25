include_guard (GLOBAL)

cmake_minimum_required (VERSION 3.27.0 FATAL_ERROR)

find_program (PLUGALYZER_PROGRAM plugalyzer DOC "Plugalyzer executable")

message (DEBUG "plugalyzer path: ${PLUGALYZER_PROGRAM}")

define_property (
	DIRECTORY
	PROPERTY CANCELLATION_REGEN_TARGET
	INHERITED
	BRIEF_DOCS "Name of custom target to drive reference file regeneration for cancellation tests in this directory"
	FULL_DOCS
		"Reference audio files for all cancellation tests in this directory can be regenerated by the custom target named in this property"
)

define_property (
	DIRECTORY
	PROPERTY CANCELLATION_OUTPUT_DIR
	INHERITED
	BRIEF_DOCS "Directory where generated audio files for cancellation tests in this directory will be written to"
	FULL_DOCS 
		"Generated audio files for all cancellation tests in this directory will be written to this output directory."
)

define_property (
	DIRECTORY
	PROPERTY CANCELLATION_EXTERNAL_DATA_TARGET
	INHERITED
	BRIEF_DOCS "Name of ExternalData target that all cancellation tests in this directory will reference"
	FULL_DOCS
		"All cancellation tests in this directory will use the named ExternalData target for resolving DATA{} references in input arguments."
)

define_property (
	DIRECTORY
	PROPERTY CANCELLATION_CONFIGS
	INHERITED
	BRIEF_DOCS "Build configurations for which to enable cancellation tests in this directory"
	FULL_DOCS
		"All cancellation tests in this directory will be enabled only for the build configurations listed in this property."
)

macro(__pct_resolve_var_path variable)
	if(MTM_ARG_EXTERNAL_DATA_TARGET)
		string (FIND "${${variable}}" "DATA{" __data_found)

		if("${__data_found}" GREATER -1)
			ExternalData_Expand_Arguments (
				"${MTM_ARG_EXTERNAL_DATA_TARGET}"
				"${variable}" "${${variable}}"
			)
		else()
			cmake_path (ABSOLUTE_PATH "${variable}" BASE_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}")
		endif()
	else()
		cmake_path (ABSOLUTE_PATH "${variable}" BASE_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}")
	endif()

	message (TRACE "Path variable ${variable} resolved to ${${variable}}")
endmacro()

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
		[SAMPLERATE <hz>]
		[OUTPUT_DIR <directory>]
		[TEST_PREFIX <prefix>]
		[REGEN_TARGET <target>]
		[EXTERNAL_DATA_TARGET <target>]
		[CONFIGS <config>...]
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

	SAMPLERATE is a value in hz (ie 44100), and may only be specified if you do not specify any INPUT_AUDIO files.

	RMS_THRESH determines how strict the test is; a value of 0 will require that the rendered audio is exactly the same
	as the reference audio with no deviation, and a value of 1 would allow a completely different audio output to
	"pass" the cancellation test. RMS threshold values may require tuning on a per-cancellation-test basis over time.
	EXACT is a shorthand for passing RMS_THRESH 0, and it is an error to specify both EXACT and an RMS_THRESH value.

	STATE_FILE is a JSON file containing parameter values, and can even describe parameter automations; see
	https://github.com/CrushedPixel/Plugalyzer for more details about the file format. Non-automated parameter values
	can also be set individually using the PARAMS keyword. For PARAMS, you can specify the parameter name or index.

	OUTPUT_DIR defines where the generated audio files will be written. The files will actually be generated in a
	build-configuration-specific subdirectory beneath OUTPUT_DIR. If not specified, the value of the CANCELLATION_OUTPUT_DIR
	directory property will be used, if set; otherwise, this defaults to ${CMAKE_CURRENT_BINARY_DIR}/cancellation-generated.

	TEST_PREFIX defines a prefix for the test names, and defaults to <pluginTarget>.Cancellation.<ReferenceFileName>

	REGEN_TARGET can be the name of a custom target that will be created to drive regeneration of the reference audio file 
	using the supplied inputs and parameters. If not specified, the value of the CANCELLATION_REGEN_TARGET directory property 
	will be used, if set. Multiple reference files can be regenerated using the same custom target. 

	EXTERNAL_DATA_TARGET can be the name of an ExternalData data management target. If EXTERNAL_DATA_TARGET is specified,
	then you can use ExternalData's DATA{} syntax in the arguments REFERENCE_AUDIO, INPUT_AUDIO, INPUT_MIDI and STATE_FILE.
	If not specified, defaults to the value of the CANCELLATION_EXTERNAL_DATA_TARGET directory property, if set. Has no effect
	if no DATA{} references are found in the input arguments.

	CONFIGS can be a list of build configurations for which to enable the cancellation tests. If not specified, then if the
	CANCELLATION_CONFIGS directory property is set, its value will be used; otherwise, all build configurations will be
	enabled by default. One usage of this feature would be to enable cancellation tests for only the Release configuration.

	TEST_NAMES_OUT can name a variable that will be populated in the calling scope with the names of the generated tests.
	This will be a list of 2 values, since each cancellation test is implemented using a render command and a diff command.

	Relative paths for all input variables are evaluated relative to CMAKE_CURRENT_SOURCE_DIR, except for OUTPUT_DIR,
	which is evaluated relative to CMAKE_CURRENT_BINARY_DIR.

	Directory properties:
		- CANCELLATION_REGEN_TARGET
		- CANCELLATION_OUTPUT_DIR
		- CANCELLATION_EXTERNAL_DATA_TARGET
		- CANCELLATION_CONFIGS

	Cache variables:
		- PLUGALYZER_PROGRAM
]]
function (add_plugin_cancellation_test pluginTarget)

	list (APPEND CMAKE_MESSAGE_INDENT "  - ${CMAKE_CURRENT_FUNCTION}: ")
	list (APPEND CMAKE_MESSAGE_CONTEXT "${CMAKE_CURRENT_FUNCTION}")

	if (NOT TARGET "${pluginTarget}")
		message (FATAL_ERROR "Plugin target '${pluginTarget}' does not exist!")
	endif ()

	get_property (is_set TARGET "${pluginTarget}" PROPERTY JUCE_PLUGIN_ARTEFACT_FILE SET)

	if(NOT is_set)
		message (FATAL_ERROR 
			"JUCE_PLUGIN_ARTEFACT_FILE not defined for target ${pluginTarget}. Is it an audio plugin created with juce_add_plugin?"
		)
	endif()

	get_target_property (plugin_artefact "${pluginTarget}" JUCE_PLUGIN_ARTEFACT_FILE)

	#[[ ----------------------------------------------------------------------------------------------------------- ]]

	list (APPEND CMAKE_MESSAGE_CONTEXT "ArgumentParsingAndValidating")

	set (options
		EXACT
	)

	set (
		oneVal
		BLOCKSIZE
		EXTERNAL_DATA_TARGET
		INPUT_MIDI
		OUTPUT_DIR
		REFERENCE_AUDIO
		REGEN_TARGET
		RMS_THRESH
		SAMPLERATE
		SIDECHAIN_INPUT
		STATE_FILE
		TEST_PREFIX
		TEST_NAMES_OUT
	)

	set (
		multiVal
		INPUT_AUDIO
		PARAMS
		CONFIGS
	)

	cmake_parse_arguments (MTM_ARG "${options}" "${oneVal}" "${multiVal}" ${ARGN})

	unset (options)
	unset (oneVal)
	unset (multiVal)

	if(MTM_ARG_TEST_NAMES_OUT)
		unset ("${MTM_ARG_TEST_NAMES_OUT}" PARENT_SCOPE)
	endif()

	if (NOT (MTM_ARG_INPUT_AUDIO OR MTM_ARG_INPUT_MIDI))
		message (FATAL_ERROR "You must specify either INPUT_AUDIO or INPUT_MIDI")
	endif ()

	if (NOT MTM_ARG_REFERENCE_AUDIO)
		message (FATAL_ERROR "Missing required argument REFERENCE_AUDIO")
	endif ()

	if(MTM_ARG_RMS_THRESH AND MTM_ARG_EXACT)
		message (FATAL_ERROR "RMS_THRESH and EXACT cannot both be specified")
	endif()

	if(MTM_ARG_SAMPLERATE AND MTM_ARG_INPUT_AUDIO)
		message (FATAL_ERROR "SAMPLERATE and INPUT_AUDIO cannot both be specified")
	endif()

	if(MTM_ARG_UNPARSED_ARGUMENTS)
		message (AUTHOR_WARNING "Ignoring unkown arguments: ${MTM_ARG_UNPARSED_ARGUMENTS}")
	endif()

	if (NOT PLUGALYZER_PROGRAM)
		message (WARNING 
			"Cannot create cancellation tests because Plugalyzer was not found. Set PLUGALYZER_PROGRAM to its path."
		)
		return ()
	endif ()

	if(NOT MTM_ARG_EXTERNAL_DATA_TARGET)
		get_directory_property (MTM_ARG_EXTERNAL_DATA_TARGET CANCELLATION_EXTERNAL_DATA_TARGET)
	endif()

	if(MTM_ARG_EXTERNAL_DATA_TARGET)
		include (ExternalData)
		message (VERBOSE "Using ExternalData target ${MTM_ARG_EXTERNAL_DATA_TARGET}")
	endif()

	if(MTM_ARG_OUTPUT_DIR)
		cmake_path (ABSOLUTE_PATH MTM_ARG_OUTPUT_DIR BASE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}")
	else()
		get_directory_property (MTM_ARG_OUTPUT_DIR CANCELLATION_OUTPUT_DIR)

		if(MTM_ARG_OUTPUT_DIR)
			cmake_path (ABSOLUTE_PATH MTM_ARG_OUTPUT_DIR BASE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}")
		else()
			set (MTM_ARG_OUTPUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/cancellation-generated")
		endif()
	endif()

	message (VERBOSE "Output directory: ${MTM_ARG_OUTPUT_DIR}")

	if(NOT MTM_ARG_CONFIGS)
		get_directory_property (MTM_ARG_CONFIGS CANCELLATION_CONFIGS)
	endif()

	if(MTM_ARG_CONFIGS)
		set (test_config_args CONFIGURATIONS ${MTM_ARG_CONFIGS})

		list (JOIN MTM_ARG_CONFIGS " " config_list)
		message (VERBOSE "Restricting tests to build configurations: ${config_list}")
		unset (config_list)
	else()
		unset (test_config_args)
	endif()

	__pct_resolve_var_path (MTM_ARG_REFERENCE_AUDIO)

	cmake_path (GET MTM_ARG_REFERENCE_AUDIO STEM filename)

	if (NOT MTM_ARG_TEST_PREFIX)
		set (MTM_ARG_TEST_PREFIX "${pluginTarget}.Cancellation.${filename}.")
	endif ()

	set (base_dir "${MTM_ARG_OUTPUT_DIR}/$<CONFIG>")

	list (POP_BACK CMAKE_MESSAGE_CONTEXT)

	#[[ ----------------------------------------------------------------------------------------------------------- ]]

	# dummy set up test to create output directory
	block (PROPAGATE setup_test)
		list (APPEND CMAKE_MESSAGE_CONTEXT "CreateSetupTest")

		# the setup test is named for the output directory and does not include the test prefix so
		# that multiple cancellation tests using the same output directory can share one setup test
		string (MD5 base_dir_hash "${base_dir}")
		set (setup_test "Cancellation.Prepare.${base_dir_hash}")

		if(NOT TEST "${setup_test}")
			add_test (
				NAME "${setup_test}"
				COMMAND "${CMAKE_COMMAND}" -E make_directory "${base_dir}"
				${test_config_args}
			)

			set_tests_properties ("${setup_test}" PROPERTIES FIXTURES_SETUP "${setup_test}")
			set_property (TEST "${setup_test}" APPEND PROPERTY LABELS Cancellation)

			message (DEBUG "Created setup test to create output directory ${base_dir} (test name ${setup_test})")
		endif()
	endblock()

	#[[ ----------------------------------------------------------------------------------------------------------- ]]

	# build plugalyzer command line
	block (PROPAGATE plugalyzer_args MTM_ARG_INPUT_MIDI MTM_ARG_STATE_FILE input_audio_files)
		list (APPEND CMAKE_MESSAGE_CONTEXT "CreatePlugalyzerCommandLine")

		if (MTM_ARG_INPUT_MIDI)
			__pct_resolve_var_path (MTM_ARG_INPUT_MIDI)
			set (midi_input_arg "--midiInput=${MTM_ARG_INPUT_MIDI}")
		else ()
			unset (midi_input_arg)
		endif ()

		if (MTM_ARG_STATE_FILE)
			__pct_resolve_var_path (MTM_ARG_STATE_FILE)
			set (param_file_arg "--paramFile=${MTM_ARG_STATE_FILE}")
		else ()
			unset (param_file_arg)
		endif ()

		if (MTM_ARG_BLOCKSIZE)
			set (blocksize_arg "--blockSize=${MTM_ARG_BLOCKSIZE}")
		else ()
			unset (blocksize_arg)
		endif ()

		if(MTM_ARG_SAMPLERATE)
			set (samplerate_arg "--sampleRate=${MTM_ARG_SAMPLERATE}")
		else()
			unset (samplerate_arg)
		endif()

		unset (input_audio_args)
		unset (input_audio_files)

		foreach(input IN LISTS MTM_ARG_INPUT_AUDIO)
			__pct_resolve_var_path (input)

			list (APPEND input_audio_args "--input=${input}")
			list (APPEND input_audio_files "${input}")
		endforeach()

		unset (explicit_param_args)

		foreach (param_arg IN LISTS MTM_ARG_PARAMS)
			list (APPEND explicit_param_args "--param=${param_arg}")
		endforeach ()

		set (
			plugalyzer_args
			"--plugin=${plugin_artefact}"
			--overwrite
			${input_audio_args} ${midi_input_arg}
			${blocksize_arg} ${samplerate_arg}
			${explicit_param_args} ${param_file_arg}
		)

		list (JOIN plugalyzer_args " " cmd_line)
		message (DEBUG "plugalyzer command line: ${cmd_line}")
	endblock()

	#[[ ----------------------------------------------------------------------------------------------------------- ]]

	# create render test

	list (APPEND CMAKE_MESSAGE_CONTEXT "CreateRenderTest")

	cmake_path (GET MTM_ARG_REFERENCE_AUDIO EXTENSION extension)

	set (generated_audio "${base_dir}/${filename}${extension}")

	message (DEBUG "Generated audio path: ${generated_audio}")

	set (process_test "${MTM_ARG_TEST_PREFIX}Render")

	message (DEBUG "Render test name: ${process_test}")

	add_test (
		NAME "${process_test}"
		COMMAND
			"${PLUGALYZER_PROGRAM}" process ${plugalyzer_args}
			"--output=${generated_audio}"
		${test_config_args}
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

	list (POP_BACK CMAKE_MESSAGE_CONTEXT)

	#[[ ----------------------------------------------------------------------------------------------------------- ]]

	# create diff test

	list (APPEND CMAKE_MESSAGE_CONTEXT "CreateDiffTest")

	set (diff_test "${MTM_ARG_TEST_PREFIX}Diff")

	message (DEBUG "Diff test name: ${diff_test}")

	if (NOT MTM_ARG_RMS_THRESH)
		if(MTM_ARG_EXACT)
			set (MTM_ARG_RMS_THRESH 0.0)
		else()
			set (MTM_ARG_RMS_THRESH 0.005)
		endif()
	endif ()

	message (DEBUG "RMS threshold: ${MTM_ARG_RMS_THRESH}")

	add_test (NAME "${diff_test}"
			  COMMAND cancellation::audio_diff
					  "${MTM_ARG_REFERENCE_AUDIO}" "${generated_audio}" "${MTM_ARG_RMS_THRESH}"
			  ${test_config_args}
	)

	set_tests_properties (
		"${diff_test}"
		PROPERTIES
			FIXTURES_REQUIRED "${process_test}"
			REQUIRED_FILES "${MTM_ARG_REFERENCE_AUDIO};${generated_audio}"
			ATTACHED_FILES "${MTM_ARG_REFERENCE_AUDIO};${generated_audio}"
	)

	set_property (
		TEST "${process_test}" "${diff_test}" 
		APPEND PROPERTY LABELS 
		Cancellation "${pluginTarget}"
	)

	if(MTM_ARG_TEST_NAMES_OUT)
		set ("${MTM_ARG_TEST_NAMES_OUT}" "${process_test};${diff_test}" PARENT_SCOPE)
	endif()

	set_property (DIRECTORY APPEND PROPERTY ADDITIONAL_CLEAN_FILES "${generated_audio}")

	message (VERBOSE "Added plugin cancellation test ${MTM_ARG_TEST_PREFIX}")

	list (POP_BACK CMAKE_MESSAGE_CONTEXT)

	#[[ ----------------------------------------------------------------------------------------------------------- ]]

	# create regen command

	# TODO: regen command currently isn't restricted to the set of configurations specified for the tests
	# we could wrap this command in a script that checks if the configuration is in that list...

	list (APPEND CMAKE_MESSAGE_CONTEXT "CreateRegenCommand")

	if (NOT MTM_ARG_REGEN_TARGET)
		get_directory_property (MTM_ARG_REGEN_TARGET CANCELLATION_REGEN_TARGET)

		if (NOT MTM_ARG_REGEN_TARGET)
			return ()
		endif ()
	endif ()

	if(NOT TARGET "${MTM_ARG_REGEN_TARGET}")
		add_custom_target (
			"${MTM_ARG_REGEN_TARGET}"
			COMMENT "Finished regenerating cancellation reference audio files"
			VERBATIM
		)

		set_target_properties (
			"${MTM_ARG_REGEN_TARGET}" PROPERTIES FOLDER cancellation-tests/
		)

		set_property (
			TARGET "${MTM_ARG_REGEN_TARGET}" APPEND PROPERTY LABELS Cancellation
		)

		message (VERBOSE "Created cancellation regeneration target ${MTM_ARG_REGEN_TARGET}")
	else()
		message (VERBOSE "Using cancellation regeneration target ${MTM_ARG_REGEN_TARGET}")
	endif()

	set (update_reference_output "${MTM_ARG_TEST_PREFIX}${filename}_regenerate")

	if(MTM_ARG_EXTERNAL_DATA_TARGET)
		set (data_depend "${MTM_ARG_EXTERNAL_DATA_TARGET}")
	else()
		unset (data_depend)
	endif()

	add_custom_command (
		OUTPUT "${update_reference_output}"
		COMMAND
			"${PLUGALYZER_PROGRAM}" process ${plugalyzer_args}
			"--output=${MTM_ARG_REFERENCE_AUDIO}"
		DEPENDS "${pluginTarget}" ${input_audio_files} ${MTM_ARG_INPUT_MIDI} ${MTM_ARG_STATE_FILE} ${data_depend}
		DEPENDS_EXPLICIT_ONLY
		COMMENT "Regenerating reference audio file ${filename}${extension} for plugin cancellation test ${MTM_ARG_TEST_PREFIX}..."
		VERBATIM COMMAND_EXPAND_LISTS
	)

	set_source_files_properties ("${update_reference_output}" PROPERTIES SYMBOLIC ON)

	target_sources ("${MTM_ARG_REGEN_TARGET}" PRIVATE "${update_reference_output}")

	message (VERBOSE 
		"Added reference file regeneration command for plugin cancellation test ${MTM_ARG_TEST_PREFIX}"
		" - file ${filename} - regeneration target name: ${MTM_ARG_REGEN_TARGET}"
	)

endfunction ()
