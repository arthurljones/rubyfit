require "rubyfit/message_writer"

class RubyFit::Writer
  def write(stream, opts = {})
    raise "Can't start write mode from #{@state}" if @state
    @state = :write
    @local_nums = {}
    @last_local_num = -1

    @stream = stream

    %i(start_time end_time course_point_count track_point_count name
       total_distance time_created start_x start_y end_x end_y).each do |key|
      raise ArgumentError.new("Missing required option #{key}") unless opts[key]
    end

    start_time = opts[:start_time].to_i
    end_time = opts[:end_time].to_i
    
    @data_crc = 0

    # Calculate data size to put in header
    definition_sizes = %i(file_id course lap course_point record)
      .map{|type| RubyFit::MessageWriter.definition_message_size(type) }
      .reduce(&:+)

    data_sizes = {
      file_id: 1,
      course: 1,
      lap: 1,
      course_point: opts[:course_point_count], 
      record: opts[:track_point_count]
    }
      .map{|type, count| RubyFit::MessageWriter.data_message_size(type) * count }
      .reduce(&:+)

    data_size = definition_sizes + data_sizes
    write_data(RubyFit::MessageWriter.file_header(data_size))

    write_message(:file_id, {
      time_created: opts[:time_created],
      type: 6, # Course file
      manufacturer: 1, # Garmin
      product: 0,
      serial_number: 0,
    })

    write_message(:course, { name: opts[:name] })

    write_message(:lap, {
      start_time: start_time,
      timestamp: end_time,
      start_x: opts[:start_x],
      start_y: opts[:start_y],
      end_x: opts[:end_x],
      end_y: opts[:end_y],
      total_distance: opts[:total_distance]
    })

    yield

    write_data(RubyFit::MessageWriter.crc(@data_crc))
    @state = nil
  end

  def course_points
    raise "Can only start course points mode inside 'write' block" if @state != :write
    @state = :course_points
    yield
    @state = :write
  end

  def track_points
    raise "Can only write track points inside 'write' block" if @state != :write
    @state = :track_points
    yield
    @state = :write
  end

  def course_point(values)
    raise "Can only write course points inside 'course_points' block" if @state != :course_points
    write_message(:course_point, values)
  end

  def track_point(values)
    raise "Can only write track points inside 'track_points' block" if @state != :track_points
    write_message(:record, values)
  end

  protected
  
  def write_message(type, values)
    local_num = @local_nums[type]
    unless local_num
      @last_local_num += 1
      local_num = @last_local_num
      write_data(RubyFit::MessageWriter.definition_message(type, local_num))
      @local_nums[type] = local_num
    end

    write_data(RubyFit::MessageWriter.data_message(type, local_num, values))
  end

  def write_data(data)
    @stream.write(data)
    prev = @data_crc
    @data_crc = RubyFit::CRC.update_crc(@data_crc, data)
  end
end
