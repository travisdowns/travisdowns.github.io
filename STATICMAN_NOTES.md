
Up to date version:

https://github.com/eduardoboucas/staticman/issues/318#issuecomment-552755165


new account for github bot:

verify email in private window


generate token:
https://github.com/settings/tokens
Settings -> Developer settings -> Personal access tokens

gist with the steps:
https://gist.github.com/jannispaul/3787603317fc9bbb96e99c51fe169731


RSA_PRIVATE_KEY:

ssh-keygen -t rsa -b 4096 -C "staticman key"
cat ~/.ssh/staticman_key | tr -d '\n' | xsel -b


heroku config:add --app staticman-travisdownsio "RSA_PRIVATE_KEY=$(cat ~/.ssh/staticman_key | tr -d '\n')"
heroku config:add --app staticman-travisdownsio "GITHUB_TOKEN=$(xsel -b)"

## Create staticman.yml config file

template:
https://raw.githubusercontent.com/eduardoboucas/staticman/master/staticman.sample.yml

change:
name

## Accept Invite to Blog Repo

https://staticman-travisdownsio.herokuapp.com/v2/connect/travisdowns/blog-test

## Set Up Comments on Blog Post

staticman_url in root config.yml

export HEROKU_APP=staticman-travisdownsio

## Refs

https://spinningnumbers.org/a/staticman.html
https://gist.github.com/jannispaul/3787603317fc9bbb96e99c51fe169731



