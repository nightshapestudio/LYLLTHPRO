"""WAV in and out with scipy only (float32 stereo)."""
import numpy as np
from scipy.io import wavfile


def read(path):
    rate, data = wavfile.read(path)
    data = data.astype(np.float64)
    if data.ndim == 1:
        data = np.stack([data, data], axis=1)
    return data, rate


def write(path, data, rate=48000):
    wavfile.write(path, rate, np.asarray(data, dtype=np.float32))
