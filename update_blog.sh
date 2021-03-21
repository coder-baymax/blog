cd ~/github/blog
git pull
bundle install
bundle exec jekyll build
find _site -name '*.html' | xargs sed -i -e 's/\.\.\/img\/in-post/\/img\/in-post/g'
docker stop blog
docker rm blog
docker run -d -p 80:80 --restart=always --name blog -v $(pwd)/_site:/usr/share/nginx/html nginx
