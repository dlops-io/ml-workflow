#!/bin/bash
# This image runs in two modes:
#   1. Locally, via docker-shell.sh: no arguments are passed, so we open a shell
#      and you run `python cli.py ...` yourself.
#   2. As a step in a Vertex AI Pipeline: the pipeline passes the arguments
#      (see ContainerSpec args in src/workflow/cli.py), e.g.
#      "cli.py --search --nums 10 ...", and we run that command and exit.

echo "Container is running!!!"
echo "Architecture: $(uname -m)"
echo "Environment ready! Virtual environment activated."
echo "Python version: $(python --version)"
echo "UV version: $(uv --version)"

args="$@"
echo $args

# Activate virtual environment
echo "Activating virtual environment..."
source /.venv/bin/activate

if [[ -z ${args} ]]; 
then
    # Mode 1 (local): no arguments, keep a shell open
    exec /bin/bash
else
  # Mode 2 (pipeline step): run the given cli.py command; the container exits when it finishes
  uv run python $args
fi


