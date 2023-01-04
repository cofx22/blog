Title: Browser beats II: synthesizing a snare drum and a hi-hat
Date: 2020-05-25
Tags: Browser beats
Canonical-URL: https://www.kabisa.nl/tech/browser-beats-ii-synthesizing-a-snare-drum-and-a-hi-hat

*This post first appeared on [Kabisa's Tech Blog](https://www.kabisa.nl/tech/).*

In the previous installment of browser beats, we used the [Web Audio API](https://developer.mozilla.org/en-US/docs/Web/API/Web_Audio_API) to synthesize a kick drum.
This time, we’ll look at snares and hi-hats.
Once you know how to synthesize kicks, snares and hi-hats are not far away.

## Snare

The snare sound we’ll synthesize consists of two components.
One component represents the vibrating skins of the snare drum, the other represents the vibrating snares.
For the first component, we’ll use two sine-like waves, one at 185Hz and the other at 349Hz.
I took these values from a [MusicTech tutorial](https://www.musictech.net/tutorials/modular-eurorack-snare-tutorial/).
An article in [Sound on Sound](https://www.soundonsound.com/techniques/practical-snare-drum-synthesis) mentions 180Hz and 330Hz.
Obviously, you should go with whatever frequencies sound best to you.

```
const playSnare = () => {
    const lowTriangle = audioContext.createOscillator();
    lowTriangle.type = 'triangle';
    lowTriangle.frequency.value = 185;

    const highTriangle = audioContext.createOscillator();
    highTriangle.type = 'triangle';
    highTriangle.frequency.value = 349;

    const lowWaveShaper = audioContext.createWaveShaper();
    lowWaveShaper.curve = distortionCurve(5);

    const highWaveShaper = audioContext.createWaveShaper();
    highWaveShaper.curve = distortionCurve(5);

    const lowTriangleGainNode = audioContext.createGain();
    lowTriangleGainNode.gain.value = 1;
    lowTriangleGainNode.gain.linearRampToValueAtTime(0, audioContext.currentTime + 0.1)

    const highTriangleGainNode = audioContext.createGain();
    highTriangleGainNode.gain.value = 1;
    highTriangleGainNode.gain.linearRampToValueAtTime(0, audioContext.currentTime + 0.1)

    const snareGainNode = audioContext.createGain();
    snareGainNode.gain.value = 1;

    lowTriangle.connect(lowWaveShaper);
    lowWaveShaper.connect(lowTriangleGainNode);
    lowTriangleGainNode.connect(snareGainNode);
    snareGainNode.connect(audioContext.destination);

    highTriangle.connect(highWaveShaper);
    highWaveShaper.connect(highTriangleGainNode);
    highTriangleGainNode.connect(snareGainNode);

    lowTriangle.start(audioContext.currentTime);
    lowTriangle.stop(audioContext.currentTime + 1);

    highTriangle.start(audioContext.currentTime);
    highTriangle.stop(audioContext.currentTime + 1);
};
```

Together, these two sound like this:

<audio controls="" src="https://ljpengelen.github.io/groovid19/snare-and-hihat/audio/sines.mp3"></audio>

We could have used pure sines waves here.
There’s no need for applying the trick we used for the kick drum.
What you’re witnessing here is a sheer waste of processing power due to my unwillingness to refactor this code right now.
Let’s just say that I like the slightly more metallic sound of the distorted traingle waves.

We’ll use white noise again to represent the second component.
This time, we’ll use a filter to cut of all frequencies below 2kHz.

```
const playSnare = () => {

    ...

    const noise = whiteNoiseBufferSource();

    const noiseGainNode = audioContext.createGain();
    noiseGainNode.gain.value = 1;
    noiseGainNode.gain.linearRampToValueAtTime(0, audioContext.currentTime + 0.2);

    const noiseFilter = audioContext.createBiquadFilter();
    noiseFilter.type = 'highpass';
    noiseFilter.frequency.value = 2000;

    noise.connect(noiseGainNode);
    noiseGainNode.connect(noiseFilter);
    noiseFilter.connect(snareGainNode);

    noise.start(audioContext.currentTime);
    noise.stop(audioContext.currentTime + 1);
};
```

The filtered noise sounds like this:

<audio controls="" src="https://ljpengelen.github.io/groovid19/snare-and-hihat/audio/snare-noise.mp3"></audio>

Finally, the distorted sines and the noise together sound like this:

<audio controls="" src="https://ljpengelen.github.io/groovid19/snare-and-hihat/audio/snare.mp3"></audio>

## Hi-hat

Some filtered white noise is all you need for a hi-hat.
We again cut all frequencies below 2kHz.
This time, the volume should fade to zero in 100 milliseconds.

```
const playHiHat = () => {
    const noise = whiteNoiseBufferSource();

    const noiseGainNode = audioContext.createGain();
    noiseGainNode.gain.value = 1;
    noiseGainNode.gain.setValueAtTime(1, audioContext.currentTime + 0.001);
    noiseGainNode.gain.linearRampToValueAtTime(0, audioContext.currentTime + 0.1);

    const noiseFilter = audioContext.createBiquadFilter();
    noiseFilter.type = 'highpass';
    noiseFilter.frequency.value = 2000;

    const hiHatGainNode = audioContext.createGain();
    hiHatGainNode.gain.value = 0.3;

    noise.connect(noiseGainNode);
    noiseGainNode.connect(noiseFilter);
    noiseFilter.connect(hiHatGainNode);
    hiHatGainNode.connect(audioContext.destination);

    hiHatGainNode.connect(analyser)

    noise.start(audioContext.currentTime);
    noise.stop(audioContext.currentTime + 1);
};
```

The end result sounds like this:

<audio controls="" src="https://ljpengelen.github.io/groovid19/snare-and-hihat/audio/hihat-noise.mp3"></audio>

## Conclusion

The snare and hi-hat we’ve produced here are pretty basic.
If you want to dig deeper to achieve prettier or more realistic results, the following articles would be good starting points:

* [https://www.soundonsound.com/techniques/practical-snare-drum-synthesis](https://www.soundonsound.com/techniques/practical-snare-drum-synthesis)
* [https://www.soundonsound.com/techniques/practical-cymbal-synthesis](https://www.soundonsound.com/techniques/practical-cymbal-synthesis)

Don’t forget to put these sounds to the test by playing along with your favorite songs: [https://ljpengelen.github.io/groovid19/kick-snare-hihat.html](https://ljpengelen.github.io/groovid19/kick-snare-hihat.html).
