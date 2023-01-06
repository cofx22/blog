#!/bin/sh
bb quickblog clean
git clone -b deploy https://github.com/cofx22/blog.git public
bb quickblog render
cd public
git add .
git commit -m "Deploy"
git push
cd ..
