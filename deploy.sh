#!/bin/sh
bb quickblog clean
git clone -b deploy https://github.com/cofx22/blog.git public
rm -rf public/*
printf "%s" "blog.cofx.nl" > public/CNAME
bb quickblog render
cd public
git add .
git commit -m "Deploy"
git push
cd ..
