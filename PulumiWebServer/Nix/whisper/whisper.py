import subprocess
import os
from typing import AnyStr
import re
from flask import Flask, Response, request, render_template_string
import waitress
import tempfile

app = Flask(__name__)

youtube_regex = re.compile(
    r"^(?:https?://)?(?:www\.)?(?:youtu\.be/|youtube\.com/(?:embed/|v/|watch\?v=|watch\?.+&v=))((\w|-){11})(?:\S+)?$")

alnum_regex = re.compile(r"^[a-zA-Z0-9]+$")


def generate_output(wav_file):
    process = subprocess.Popen([whisper, "--file", f"/tmp/whisper/{wav_file}.wav", "--output-txt"],
                               stdout=subprocess.PIPE, bufsize=1,
                               text=True)

    yield f'event: started\ndata: {wav_file}\n\n'

    for line in iter(process.stdout.readline, ''):
        yield f"data: {line}\n\n"

    yield 'event: quit\ndata: \n\n'

    os.remove(f"/tmp/whisper/{wav_file}.wav")


def obtain_youtube(url: AnyStr) -> str:
    # handle, temp_file = tempfile.mkstemp(".wav", text=False)
    # os.close(handle)
    # os.remove(temp_file)

    # output = subprocess.run(
    #     [ytdlp, '--extract-audio', '--audio-format', 'wav', '--cookies', '/tmp/cookies.txt', '--audio-quality', '16k', '--force-ipv6', '--output', temp_file,
    #      url], check=True, capture_output=True, text=True)
    # if "429 Too Many Requests" in output.stdout:
    #     raise subprocess.CalledProcessError(1, whisper, "YouTube replied saying Too Many Requests")
    # return temp_file

    raise Exception("DigitalOcean is rate limited to YouTube")


def normalize(path: str, output: str):
    try:
        subprocess.run([normalize_binary, path, output], check=True)
    except subprocess.CalledProcessError:
        os.remove(path)
        return Response("failed to normalize", status=500)


@app.route('/transcribe-youtube')
def transcribe_youtube():
    try:
        url = request.args.get('url')
    except KeyError:
        return Response("must have a URL in the format ?url=https://www.youtube.com/watch?v=...", status=400)
    if youtube_regex.match(url) is None:
        return Response(f"url '{url}' did not appear to be a YouTube video", status=400)
    wav_file = obtain_youtube(url)
    return Response(generate_output(wav_file), mimetype="text/event-stream")


@app.route('/transcribe-file')
def transcribe_file():
    try:
        file = request.args.get('file')
    except KeyError:
        return Response("must have a file as obtained from /upload, in the format ?file=...", status=400)
    if alnum_regex.match(file) is None:
        return Response(f"filename '{file}' was not alphanumeric", status=400)
    return Response(generate_output(file), mimetype="text/event-stream")


@app.route('/transcribe-ui')
def index():
    return render_template_string(open(index_page_path).read())  # Assuming 'index.html' is in the same directory


@app.route('/upload', methods=["POST"])
def upload():
    if 'file' not in request.files:
        return 'No "file" part in request', 400
    file = request.files['file']

    # Create temp file for this upload
    handle, temp_file = tempfile.mkstemp(text=False)
    try:
        os.close(handle)
        file.save(temp_file)
        # get filename from absolute path
        temp_file_frag = os.path.basename(temp_file)

        normalize(temp_file, f"/tmp/whisper/{temp_file_frag}")
    finally:
        try:
            os.remove(temp_file)
        finally:
            pass

    return Response(temp_file_frag, mimetype="text/plain")


@app.route('/download')
def download():
    try:
        file = request.args.get('file')
    except KeyError:
        return Response("must have a file parameter", status=400)

    if alnum_regex.match(file) is None:
        return Response(f"file '{file}' was not alphanumeric, bad format", status=400)

    return Response(open(f"/tmp/whisper/{file}.wav", 'rb').read(), mimetype="audio/wav")


def run(port: int):
    waitress.serve(app, host="0.0.0.0", port=port)


if __name__ == "__main__":
    normalize_binary = os.environ["WHISPER_NORMALIZE"]
    whisper = os.environ["WHISPER_CLIENT"]
    index_page_path = os.environ["INDEX_PAGE_PATH"]
    ytdlp = os.environ["YT_DLP"]
    run(int(os.environ["WHISPER_PORT"]))
