#!/usr/bin/env bash

alias pylint=pylint_runner

case "$OSTYPE" in
    win*|msys*)
        # alias python=/usr/bin/python.exe
        # alias pip='python -m pip'
        ;;

    *)
        ;;
esac

function python-setup ()
{
    python -m pip install --upgrade pip

    pip install wheel

    pip install \
        poetry \
        pre-commit \
        python-dateutil \
        requests


# setuptools pyaudio SpeechRecognition --extra-index-url https://download.pytorch.org/whl/cu116  torch numpy

# pip install numpy speechrecognition pywhispercpp
# GGML_VULKAN=1 pip install git+https://github.com/absadiki/pywhispercpp
}
