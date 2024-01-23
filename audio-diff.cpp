#include <juce_audio_formats/juce_audio_formats.h>

[[nodiscard]] static inline juce::AudioFormatManager& getAudioFormatManager()
{
	struct AFM final
	{
		juce::AudioFormatManager afm;

		AFM()
		{
			afm.registerBasicFormats();
		}
	};

	static AFM storage;

	return storage.afm;
}

using AudioBuffer = juce::AudioBuffer<float>;

[[nodiscard]] std::optional<AudioBuffer> readBufferFromFile (const juce::File& file)
{
	if (! file.existsAsFile())
	{
		std::cerr << "Input file '" << file.getFullPathName() << "' does not exist!" << std::endl;
		return std::nullopt;
	}

	std::unique_ptr<juce::AudioFormatReader> reader { getAudioFormatManager().createReaderFor (file) };

	if (! reader)
	{
		std::cerr << "Could not create reader for input file '" << file.getFullPathName() << '\'' << std::endl;
		return std::nullopt;
	}

	const auto numChannels = static_cast<int> (reader->numChannels);
	const auto numSamples  = static_cast<int> (reader->lengthInSamples);

	AudioBuffer inputAudio;

	inputAudio.setSize (numChannels, numSamples);

	reader->read (&inputAudio, 0, numSamples, 0, true, true);

	return inputAudio;
}

[[nodiscard]] float calculateDifferenceRMS (const AudioBuffer& reference, const AudioBuffer& test)
{
	const auto numSamples  = std::min (reference.getNumSamples(), test.getNumSamples());
	const auto numChannels = std::min (reference.getNumChannels(), test.getNumChannels());

	AudioBuffer difference { numChannels, numSamples };

	for (auto chan = 0; chan < numChannels; ++chan)
	{
		difference.copyFrom (chan, 0, test, chan, 0, numSamples);

		juce::FloatVectorOperations::subtract (difference.getWritePointer(chan),
											   reference.getReadPointer(chan),
											   numSamples);
	}

	float totalRMS = 0.f;

	for (auto chan = 0; chan < numChannels; ++chan)
		totalRMS += difference.getRMSLevel(chan, 0, numSamples);

	return totalRMS / static_cast<float> (numChannels);
}

struct PrecisionRestorer final
{
	explicit PrecisionRestorer (std::ios_base& base)
		: ios (base)
		, defaultPrecision (ios.precision())
	{
	}

	~PrecisionRestorer()
	{
		ios.precision (defaultPrecision);
	}

private:
	std::ios_base&	ios;
	std::streamsize defaultPrecision;
};

int main (int argc, char** argv)
{
	//const juce::ScopedJuceInitialiser_GUI juceInit;

	if (argc != 4)
	{
		std::cerr << "Usage: \naudio-diff <referenceFile> <generatedAudio> <rmsThresh>" << std::endl;
		return EXIT_FAILURE;
	}

	std::cout << "Reading reference audio file...\n";

	const juce::File referenceFile { argv[1] };

	const auto refAudio = readBufferFromFile (referenceFile);

	if (! refAudio)
		return EXIT_FAILURE;

	std::cout << "Reading generated audio file...\n";

	const auto testAudio = readBufferFromFile (juce::File{ argv[2] });

	if (! testAudio)
		return EXIT_FAILURE;

	const auto rmsThresh = juce::String { argv[3] }.getDoubleValue();

	const auto actualRMS = calculateDifferenceRMS (*refAudio, *testAudio);

	const PrecisionRestorer raii { std::cout };

	std::cout << std::fixed << std::setprecision (6)
			  << std::endl
			  << "<CTestMeasurement type=\"numeric/double\""
			  << " name=\"" << referenceFile.getFileName() << " - RMS\">"
			  << actualRMS
			  << "</CTestMeasurement>"
			  << std::endl;

	if (actualRMS > rmsThresh)
	{
		std::cerr << "Cancellation test failed: detected SNR of " << actualRMS
				  << " which exceeds the test threshold of " << rmsThresh
				  << std::endl;

		return EXIT_FAILURE;
	}

	return EXIT_SUCCESS;
}
