module RayyanScrapers
  class DummyLogger
    def method_missing(method_sym, *arguments, &block)
      # swallow
    end
  end
end