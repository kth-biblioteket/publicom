#!/bin/bash

# Check if the file exists
if [ -f /tmp/remaining_time.txt ]; then
    # If the file exists, display its content
    cat /tmp/remaining_time.txt
else
    # If the file does not exist, show blank
    echo ""
fi
