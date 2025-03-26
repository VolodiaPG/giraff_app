from vosk import Model, KaldiRecognizer, SetLogLevel
from io import BytesIO
import os
import wave


SetLogLevel(-1)


def handle(raw_file):
    file = BytesIO(raw_file)

    wf = wave.open(file, "rb")

    if wf.getnchannels() != 1 or wf.getsampwidth() != 2 or wf.getcomptype() != "NONE":
        print("Audio file must be WAV format mono PCM.")
        sys.exit(1)

    model = Model(os.getenv("VOSK_PATH"))

    rec = KaldiRecognizer(model, 16_000)
    rec.SetWords(True)
    rec.SetPartialWords(True)

    while True:
        data = wf.readframes(4_000)
        if len(data) == 0:
            break
        rec.AcceptWaveform(data)

    finalRecognition = rec.FinalResult()

    return finalRecognition


if __name__ == "__main__":
    import sys

    if len(sys.argv) > 1:
        file_path = sys.argv[1]
        with open(file_path, "rb") as f:
            raw_file = f.read()
    else:
        print("No file path provided.")
        sys.exit(1)

    print(handle(raw_file))
