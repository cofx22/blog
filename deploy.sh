#!/bin/sh
bb quickblog render --out-dir docs
git add .
git commit -m "Deploy"
git push
