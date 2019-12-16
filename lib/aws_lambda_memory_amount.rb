require "aws_lambda_memory_amount/version"
require "time"
require "aws-sdk-cloudwatchlogs"

PREFIX = '/aws/lambda/'
USAGE_FILTER_REGEX = /.+Duration:\s+(?<duration>\d+\.\d+)\s+ms\s+Billed\s+Duration:\s+(?<billed_duration>\d+)\s+ms\s+Memory\s+Size:\s+(?<memory_size>\d+)\s+MB\s+Max\s+Memory\s+Used:\s+(?<memory_used>\d+)\s+MB(\s+Init\s+Duration:\s+(?<init_duration>\d+\.\d+)\s+ms)*/
FILTER_KEYS = [
	'duration',
	'billed_duration',
	'memory_size',
	'memory_used',
	'init_duration'
]

def debug (log)
	puts log if ARGV[0] == 'debug'
end

module AwsLambdaMemoryAmount
  def self.list_lambda_memory_amount ()
    start = Time.now
    puts '[Start]:', start.to_s
  
    ret = {}
    cwl = Aws::CloudWatchLogs::Client.new
    log_groups = []
    result = cwl.describe_log_groups({log_group_name_prefix: PREFIX})
  
    log_group_names = result.log_groups.map {|item| item.log_group_name}
    log_groups.push(log_group_names).flatten!
    while(result.next_token)
      result = cwl.describe_log_groups({
        log_group_name_prefix: PREFIX,
        next_token: result.next_token
      })
      log_group_names = result.log_groups.map {|item| item.log_group_name}
      log_groups.push(log_group_names).flatten!
    end
  
    log_groups.each do |log_group_name|
      debug "[log_group_name]: #{log_group_name}"
  
      result = cwl.describe_log_streams({
        log_group_name: log_group_name,
        order_by: 'LastEventTime',
        descending: true,
        limit: 1
      })
      # puts result
      log_stream = {}
      if result[:log_streams].length <= 0
        next
      end 
      log_stream = result[:log_streams][0]
      events = cwl.filter_log_events({
        log_group_name: log_group_name,
        log_stream_names: [log_stream[:log_stream_name]],
        filter_pattern: 'REPORT RequestId Duration',
        limit: 10
      }).events
  
      if events.length <= 0
        debug "[log_group_name]: #{log_group_name} No events" 
        next
      end
  
      # puts events
      ave = {}
      FILTER_KEYS.each {|key| ave[key] = 0}
      events.each do |item|
        m = item.message
        debug "[log_group_name][Message]: #{log_group_name} ==> #{m}"
        # puts m
        result = USAGE_FILTER_REGEX.match(m)
        FILTER_KEYS.each do |key|
          # puts key
          # puts result[key]
          unless result[key].nil?
            ave[key] = ave[key] + result[key].to_i
          end
        end
      end
      debug "[log_group_name][Sum]:"
      debug ave
  
      # puts ave
      if ave.keys.length > 0
        FILTER_KEYS.each do |key|
          ave[key] = ave[key] / events.length 
        end
        debug "[log_group_name][Ave]:"
        debug ave
        ret[log_group_name] = ave
      end
    end
    finish = Time.now
    puts '[Finish]', finish.to_s
    puts '[Duration]', finish - start 
    ret
  end
end
