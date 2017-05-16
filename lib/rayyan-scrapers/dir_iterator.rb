class DirIterator
  def initialize(dir)
    raise "Missing directory argument" if dir.nil?
    raise "Directory #{dir} does not exist" unless Dir.exist? dir
    files = Dir.entries(dir)
    raise "Directory #{dir} is empty" if files.length == 0
    @dir = dir
    @files = files
  end

  def count
    @files.count
  end

  def iterate
    raise "Give me a block to call it on each file" unless block_given?

    Dir.chdir @dir do
      pbar = ProgressBar.new(self.count) rescue nil
      @files.each do |file|
        begin
          next if file.start_with? '.'
          yield file
        rescue
          # oh man! This won't stop me from running to the end!
        ensure
          pbar.increment! if pbar
        end # rescue
      end # each file
    end # chdir
  end
end