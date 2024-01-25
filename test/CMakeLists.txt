juce_add_plugin (
	cancellation-test
	FORMATS VST3
)

target_sources (cancellation-test PRIVATE plugin.cpp)

target_link_libraries (cancellation-test PRIVATE juce::juce_audio_processors)

target_compile_definitions (cancellation-test PRIVATE JUCE_VST3_CAN_REPLACE_VST2=0)

set_directory_properties (PROPERTIES CANCELLATION_REGEN_TARGET CancellationTestRegen)

add_plugin_cancellation_test (
	cancellation-test_VST3
	INPUT_AUDIO input.wav
	REFERENCE_AUDIO "$<CONFIG>/output.wav"
	PARAMS "Gain:0.5"
	EXACT
	TEST_NAMES_OUT test_names
)

list (LENGTH test_names len)

if(NOT "${len}" EQUAL 2)
	message (FATAL_ERROR "TEST_NAMES_OUT returned a list of length ${len}")
endif()
