cd ~/github/blog
git pull
bundle install
bundle exec jekyll build
docker stop blog
docker rm blog
docker run -d -p 80:80 --name blog -v $(pwd)/_site:/usr/share/nginx/html nginx
