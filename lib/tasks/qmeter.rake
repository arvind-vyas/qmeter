require 'erb'
require 'qmeter/string'
require 'terminal-table'

namespace :qmeter do
  desc "Run brakeman and metric_fu to generate report of code"

  ### @arvind: This will run command to generate brakeman and matric fu report ###
  task :generate_report do
    puts "*** run brakeman ***"
    system "brakeman -o report.html -o report.json"

    puts "*** run metric_fu ***"
    system "metric_fu --out #{Rails.root}/public/metric_fu "
  end

  task :add_command_in_post_commit do
    ### @arvind:  Asked user to add rake command inside git post commit file , Task will run in each eommit
    STDOUT.puts "Write Y to add rake qmeter:run command to 'post commit', it will run when you commit the code".reverse_color
    input = STDIN.gets.strip
    if input == 'y' || input == 'Y'
      File.open('.git/hooks/post-commit', 'a') do |f|
        f.puts "rake qmeter:run"
      end
      system "chmod +x .git/hooks/post-commit"
    else
      STDOUT.puts "You can add it in next time"
    end
  end

  ### *** ###
  task :run do
    if File.directory?('.git') && File.exists?('.git/config')
      ### @arvind:  this will check git post commit has rake command or not
      if File.file?('.git/hooks/post-commit')
        file =  File.read(".git/hooks/post-commit").include?('rake qmeter:run')
        if !file =  File.read(".git/hooks/post-commit").include?('rake qmeter:run')
          Rake::Task["qmeter:add_command_in_post_commit"].execute
        end
      else
        Rake::Task["qmeter:add_command_in_post_commit"].execute
      end

      ### @arvind: This always executes the task, but it doesn't execute its dependencies
      Rake::Task["qmeter:generate_report"].execute
      ### *** ###
      extend Qmeter
      self.generate_final_report
      puts "======= Saving Current Analysis Details ======="
      self.save_report
      # Initialize JavaScript and CoffeeScript functionality
      initialize_javascript_coffeescript_report unless File.exist?("#{Rails.root}/config/js_cs_config/js_error_list.txt")

      rows = []
      rows << ['Security Warning', @warnings_count]
      rows << ['Flog', @flog_average_complexity]
      rows << ['Stats', @stats_code_to_test_ratio]
      rows << ['Rails Best Practices', @rails_best_practices_total]
      table = Terminal::Table.new :title => "Qmeter Analysis", :headings => ['Type', 'Number'], :rows => rows, :style => {:width => 80}
      puts table

      puts "======= Please visit localhost:3000/qmeter for detailed report ======="
    else
      puts "======= Please Initialize git first =======".bold.green.bg_red
    end
  end

  # This will append Files/Folders in .gitignore file
  task :gitignore do
    add_to_gitignore("qmeter.csv")
    add_to_gitignore("report.json")
    add_to_gitignore("report.html")
    add_to_gitignore("public/metric_fu")
    add_to_gitignore("config/js_cs_config")
  end

  def add_to_gitignore(file_folder)
    resource = file_folder.to_s
    unless File.read('.gitignore').include?(resource)
      gitignore_file = File.open('.gitignore', 'a')
      gitignore_file.puts(resource)
      gitignore_file.close_write
    end
  end

  def initialize_javascript_coffeescript_report
    puts "======= Initializing for JavsScript CoffeeScript reports =======".reverse_color
    open("#{Rails.root}/Gemfile", 'a') { |f| f.puts "gem 'jshint'" } unless (File.read('Gemfile').include?("gem 'jshint'") || File.read('Gemfile').include?('gem "jshint"'))
    open("#{Rails.root}/Gemfile", 'a') { |f| f.puts "gem 'coffeelint'" } unless (File.read('Gemfile').include?("gem 'coffeelint'") || File.read('Gemfile').include?('gem "coffeelint"'))
    system('bundle')
    system('mkdir config/js_cs_config') unless File.directory?("#{Rails.root}/config/js_cs_config")
    File.open("config/js_cs_config/coffeelint.json", 'w') do |f|
      f.write('{ "max_line_length": { "value": 120 }, "no_tabs": { "level": "ignore" } }')
    end
  end

end