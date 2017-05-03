# https://github.com/rails/rails/blob/master/activesupport/lib/active_support/core_ext/regexp.rb

class Regexp #:nodoc:
  def multiline?
    options & MULTILINE == MULTILINE
  end

  def match?(string, pos = 0)
    !!match(string, pos)
  end unless //.respond_to?(:match?)
end
