#include <juce_audio_processors/juce_audio_processors.h>

class PassThroughPlugin final : public juce::AudioProcessor
{
public:
	PassThroughPlugin()
	{
		addParameter (gainParam = new juce::AudioParameterFloat (juce::ParameterID { "Gain", 1 },
																 "Gain",
																 juce::NormalisableRange<float>{ 0.f, 1.f },
																 1.f));
	}

private:
	using String = juce::String;

	const String getName() const final { return "Test"; }

	void prepareToPlay (double, int) final {}

	void releaseResources() final {}

	void processBlock (juce::AudioBuffer<float>& buffer, juce::MidiBuffer&) final 
	{
		buffer.applyGain (gainParam->get());
	}

	double getTailLengthSeconds() const final { return 0.; }

	bool acceptsMidi() const final { return true; }
	bool producesMidi() const final { return false; }

	virtual juce::AudioProcessorEditor* createEditor() final
	{
		return nullptr;
	}

	bool hasEditor() const final { return false; }

	int getNumPrograms() final { return 1; }
	int getCurrentProgram() final { return 1; }
	void setCurrentProgram (int) final {}
	const String getProgramName (int) final
	{
		return {};
	}

	void changeProgramName (int, const String&) final {}

	void getStateInformation (juce::MemoryBlock&) final {}

	void setStateInformation (const void*, int) final {}

	juce::AudioParameterFloat* gainParam;
};

juce::AudioProcessor* JUCE_CALLTYPE createPluginFilter()
{
	return new PassThroughPlugin;
}
