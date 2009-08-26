class Parallel
  def self.in_threads(count = 2)
    out = []
    threads = []

    count.times do |i|
      threads[i] = Thread.new do
        out[i] = yield(i)
      end
    end

    threads.each{|t| t.join }
    out
  end

  def self.in_processes(count = processor_count)
    # Start writing results into n pipes
    reads = []
    writes = []
    pids = []
    count.times do |i|
      reads[i], writes[i] = IO.pipe
      pids << Process.fork do
        Marshal.dump(yield(i), writes[i]) # Serialize result
      end
    end

    kill_on_ctrl_c(pids)

    # Collect results from pipes simultanously
    # otherwise pipes get stuck when to much is written (buffer full)
    out = []
    collectors = []
    count.times do |i|
      collectors << Thread.new do
        writes[i].close

        out[i] = ''
        while text = reads[i].gets
          out[i] += text
        end

        reads[i].close
      end
    end

    collectors.each{|c| c.join }

    out.map{|x| Marshal.load(x) } # Deserialize results
  end

  def self.map(array, options = {})
    size = if options[:in_threads]
      method = 'in_threads'
      options[:in_threads]
    else
      method = 'in_processes'
      options[:in_processes] || processor_count
    end

    results = []
    in_groups_of(array, size).each do |group|
      results += send(method, group.size) do |i|
        yield group[i]
      end
    end
    results
  end

  def self.processor_count
    case RUBY_PLATFORM
    when /darwin/
      `hwprefs cpu_count`.to_i
    when /linux/
      `cat /proc/cpuinfo | grep processor | wc -l`.to_i
    end
  end

  private

  def self.in_groups_of(array, size)
    results = []
    loop do
      slice = array[(results.size * size)...((results.size+1) * size)]
      if slice.nil? or slice.empty?
        break
      else
        results << slice
      end
    end
    results
  end

  #handle user interrup (Ctrl+c)
  def self.kill_on_ctrl_c(pids)
    Signal.trap :SIGINT do
      STDERR.puts 'Parallel execution interrupted, exiting ...'
      pids.each { |pid| Process.kill(:KILL, pid) }
      exit 1 # Quit with 'failed' signal
    end
  end
end