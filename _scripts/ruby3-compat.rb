# Compatibility shims so the pinned Jekyll 4.2.0 / Liquid 4.0.3 stack builds
# locally on Ruby 3.3+. CI uses Ruby 2.7.3 and does not load this file.
#
# Usage:
#   RUBYOPT="-r$PWD/_scripts/ruby3-compat.rb" BUNDLER_VERSION=2.6.7 \
#     bundle _2.6.7_ exec jekyll build

require 'logger'

# Jekyll::Stevenson subclasses Logger without calling super in initialize, so
# the @level_override hash that Logger 1.6+ (Ruby 3.3) expects is never set.
class Logger
  alias_method :__ruby3_compat_level, :level
  def level
    @level_override ||= {}
    __ruby3_compat_level
  end
end

# Liquid 4.0.3 calls String#untaint, which Ruby 3.2 removed.
class Object
  def untaint
    self
  end

  def tainted?
    false
  end
end
