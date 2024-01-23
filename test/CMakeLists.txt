juce_add_plugin (
	cancellation-test
	FORMATS VST3
)

target_sources (cancellation-test PRIVATE plugin.cpp)

target_link_libraries (cancellation-test PRIVATE juce::juce_audio_processors)

target_compile_definitions (cancellation-test PRIVATE JUCE_VST3_CAN_REPLACE_VST2=0)

add_plugin_cancellation_test (
	cancellation-test_VST3
	INPUT_AUDIO FemaleOoh.wav
	REFERENCE_AUDIO FemaleOoh.wav
	RMS_THRESH 0
	REGEN_TARGET CancellationTestRegen
)

add_cancellation_regeneration_target (CancellationTestRegen)
