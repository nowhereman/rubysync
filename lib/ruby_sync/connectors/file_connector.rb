#!/usr/bin/env ruby
#
#  Created by Ritchie Young on 2007-01-29.
#  Copyright (c) 2007. All rights reserved.

require 'fileutils'

module RubySync
  
  module Connectors
    
    # An abstract class that serves as the base for connectors
    # that poll a filesystem directory for files and process them
    # and/or write received events to a file.
    class FileConnector < RubySync::Connectors::BaseConnector
      
      attr_accessor :in_path  # scan this directory for suitable files
      attr_accessor :out_path # write received events to this directory
      attr_accessor :in_glob # The filename glob for incoming files
      
      
      def started
        ensure_dir_exists @in_path
        ensure_dir_exists @out_path
      end
      
      def check(&blk)
        unless in_glob
          log.error "in_glob not set on file connector. No files will be processed"
          return
        end
        log.info "#{name}: Scanning #{in_path} for #{in_glob} files..."
        Dir.chdir(in_path) do |path|
          Dir.glob(in_glob) do |filename|
            log.info "#{name}: Processing '#{filename}'"
            check_file filename, &blk
            FileUtils.mv filename, "#{filename}.bak"
          end
        end
      end
      
      # Called for each filename matching in_glob in in_path
      def check_file(filename,&blk)
      end



      
    end


  end
end
