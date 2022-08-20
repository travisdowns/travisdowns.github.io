source "https://rubygems.org"

gem "jekyll", "= 4.2.0"
# gem "jekyll-seo-tag", "= 2.7.1p", path: "../jekyll-seo-tag"
# use my fork of jekyll-seo-tag to solve issue #436, non-deterministic
# output of JSON-LD data
gem "jekyll-seo-tag", "= 2.7.1p", github: 'travisdowns/jekyll-seo-tag', branch: 'v2.7.1-patched'
# actually version "3" but upstream has not pushed out a release so the
# version in the gemspec in master remains 2.5.1
gem "minima", "= 2.5.1", path: "_minima-fork-v3"
gem "kramdown-parser-gfm", "= 1.1.0"

# If you have any plugins, put them here!
group :jekyll_plugins do
  gem "jekyll-feed"
  gem "jekyll-image-size"
end

# needed for Ruby 3 because https://github.com/jekyll/jekyll/issues/8523
# has not been fixed in a released Jekyll version
gem "webrick", "~> 1.7"
