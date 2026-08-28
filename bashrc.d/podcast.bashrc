#!/bin/bash

function podcast-download ()
{
    python -m podcast_downloader --config ~/dot-files/scripts/config/podcast-downloader.json
}
