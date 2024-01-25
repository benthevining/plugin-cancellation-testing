# Audio plugin cancellation testing

This repository provides CMake code for running audio cancellation tests with CTest.

A minimal example:
```cmake
juce_add_plugin (foo ...)

add_plugin_cancellation_test (
	foo_VST3 
	INPUT_AUDIO input.wav
	REFERENCE_AUDIO reference.wav
	RMS_THRESH 0.005
)
```

The above code will register tests that render some audio through `foo_VST3`, using `input.wav`
as the input, and check that the RMS of the noise signal (difference between input and output)
is less than 0.005.

You can also use your test definitions to drive regenerating the reference files:
```cmake
juce_add_plugin (foo ...)

add_plugin_cancellation_test (
	foo_VST3 
	INPUT_AUDIO input.wav
	REFERENCE_AUDIO reference.wav
	RMS_THRESH 0.005
	REGEN_TARGET fooReferenceAudio
)
```

With the above code, the cancellation tests will be run as normal for regular CMake build / CTest,
but if you manually build the `fooReferenceAudio` target, then it will *replace* `reference.wav`
with the output of rendering audio through `foo_VST3` using `input.wav` as the input.
