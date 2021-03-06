require "qmeter/version"
require 'qmeter/railtie' if defined?(Rails)
require "csv"
require "qmeter/engine"

module Qmeter
  def initialize_thresholds(thresholds)
    # Initialize threshold values
    @security_warnings_min = thresholds['security_warnings_min']
    @security_warnings_max = thresholds['security_warnings_max']

    @rails_best_practices_min = thresholds['rails_best_practices_min']
    @rails_best_practices_max = thresholds['rails_best_practices_max']

    @flog_complexity_min = thresholds['flog_complexity_min']
    @flog_complexity_max = thresholds['flog_complexity_max']

    @stats_ratio_min = thresholds['stats_ratio_min']
    @stats_ratio_max = thresholds['stats_ratio_max']
  end

  def collect_brakeman_details
    # Breakman source file
    file = check_and_assign_file_path('report.json')
    if file
      data_hash = JSON.parse(file)
      ### @arvind: change array to hash and check it contain warnings or not
      if data_hash.present? && data_hash.class == Hash ? data_hash.has_key?('warnings') : data_hash[0].has_key?('warnings')
        warning_type = data_hash['warnings'].map {|a| a = a['warning_type'] }
        assign_warnings(warning_type, data_hash['warnings'].count)
      elsif data_hash[0].has_key?('warning_type')
        assign_warnings([data_hash[0]['warning_type']])
      end
    end
  end

  ### @arvind: Assign warnings to @breakeman_warnings ###
  def assign_warnings(warning_type, warnings_count=1)
    @brakeman_warnings = Hash.new(0)
    # warning_type = data_hash[0]['warning_type']
    @warnings_count = warnings_count
    warning_type.each do |v|
      @brakeman_warnings[v] += 1
    end
  end

  def collect_metric_fu_details
  # parsing metric_fu report from .yml file
    file = check_and_assign_file_path('tmp/metric_fu/report.yml')
    if file
      @surveys  = YAML.load(ERB.new(file).result)
      @surveys.each do |survey|
        assign_status(survey) if survey.present?
      end
    end
  end

  ### @arvind: assing ration ,complexity and bestpractice of code ###
  def assign_status(survey)
    case survey[0]
      when :flog
        @flog_average_complexity = survey[1][:average].round(1)
      when :stats
        @stats_code_to_test_ratio = survey[1][:code_to_test_ratio]
      when :rails_best_practices
        @rails_best_practices_total = survey[1][:total].first.gsub(/[^\d]/, '').to_i
    end
  end

  def generate_final_report
    collect_metric_fu_details
    collect_brakeman_details
    @app_root = Rails.root
    get_previour_result
  end

  def save_report
    # Save report data into the CSV
    ### Hide this because we are not using this currently
    #flag = false
    #flag = File.file?("#{Rails.root}/qmeter.csv")
    CSV.open("#{Rails.root}/qmeter.csv", "a") do |csv|
      #csv << ['flog','stats','rails_best_practices','warnings', 'timestamp'] if flag == false
      sha = `git rev-parse HEAD`
      csv << [@flog_average_complexity, @stats_code_to_test_ratio, @rails_best_practices_total, @warnings_count, sha]
    end
  end

  def get_previour_result
    # Get previous report data
    @previous_reports = CSV.read("#{Rails.root}/qmeter.csv").last(4) if File.file?("#{Rails.root}/qmeter.csv")
  end

  def choose_color
    # Check threashhold
    ### @arvind: set color to the variables ###
    @brakeman_warnings_rgy = set_color(@warnings_count, @security_warnings_max,  @security_warnings_min)
    @rails_best_practices_rgy = set_color(@rails_best_practices_total, @rails_best_practices_max, @rails_best_practices_min)
    @flog_rgy = set_color(@flog_average_complexity, @flog_complexity_max, @flog_complexity_min)
    @stats_rgy = set_color(@stats_code_to_test_ratio, @stats_ratio_max, @stats_ratio_min )
  end

  ### @arvind: method to check file is exist or not ###
  def check_and_assign_file_path(path)
    file = "#{Rails.root}/#{path}"
    File.exist?(file) ? File.read(path)  : nil
  end

  ### @arvind: send proper color according to data ###
  def set_color(count, max, min)
    if count.present? && count > max
      'background-color:#D00000;'
    elsif count.present? && count > min && count < max
      'background-color:yellow;'
    else
      'background-color:#006633;'
    end
  end

  def javascript_coffeescript_reports
    system('rake jshint > config/js_cs_config/js_error_list.txt')
    file = File.new("config/js_cs_config/js_error_list.txt", "r") if File.exists?('config/js_cs_config/js_error_list.txt')

    @js_error_count = 0
    if file.present? && file.count > 0
      file.rewind
      line_count = file.count
      file.rewind
      @js_errors = {}
      file.each_with_index do |line, index|
        error_details = /(?<file_name>\w+).js: line (?<line_number>\d+), col (?<column_number>\d+),/.match(line)
        unless error_details.nil?
          file_name = error_details[:file_name] << ".js"
          line_number = error_details[:line_number]
          column_number = error_details[:column_number]
          message = line.split(',').last.strip.gsub('.',"")
          @js_errors["#{file_name}"] = [] unless @js_errors["#{file_name}"].present?
          @js_errors["#{file_name}"] << {line_number: line_number, column_number: column_number, message: message}
        end
        @js_error_count = /(?<error_count>\d+) errors/.match(line)[:error_count].to_i if (line_count - 1) == index
      end
    end

    coffee_listing = Coffeelint.lint_dir('app/assets/javascripts', :config_file => 'config/js_cs_config/coffeelint.json')

    @cs_error_count = 0
    coffee_listing.each_with_index do |files, index|
      if files.present?
        file_name = files.first.split("/").last
        @cs_errors = {}
        @cs_errors["#{file_name}"] = []
        files.each_with_index do |line, index|
          next if index == 0
          line.each_with_index do |error, index|
            column_number = (error["rule"] == "coffeescript_error") ? error["message"].split(":").third : ""
            line_number = error["lineNumber"]
            message = error["message"].split("error: ").last.split("\n").first
            @cs_errors["#{file_name}"] << {:line_number => line_number, :column_number => column_number, :message => message}
            @cs_error_count += 1
          end
        end
      end
    end
  end

end
