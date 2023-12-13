require 'zlib'
require 'rubygems'
require 'rubygems/package'
require 'fileutils'

# Helper class for tar/gz packaging and unpackaging
module Util
  module Archive
    extend self

    # Creates a gzip package from specified source
    # @param src [String] Path to source file
    # @param dst [String] Path to output gzip archive file
    # @return [String] Absolute path to output gzip archive
    def gzip(src, dst = nil)
      destination_path = dst || File.join(File.dirname(src), File.basename(src) + '.gz')
      FileUtils.mkdir_p File.dirname(destination_path)

      Zlib::GzipWriter.open(destination_path) do |gz|
        gz.mtime = File.mtime(src)
        gz.orig_name = File.basename src
        gz.write IO.binread(src)
      end
      destination_path
    end

    # Creates a gzip package from specified source file and removes source
    # @param (see #gzip)
    # @return (see #gzip)
    def gzip!(src, dst = nil)
      gzip = gzip(src, dst)
      FileUtils.rm_f src
      gzip
    end

    # Unpacks a gzip archive from specified source file to destination
    # @param src [String] Path to source file
    # @param dst [String] Path to output gzip archive file
    # @return [String] Absolute path to output file
    def gunzip(src, dst = nil)
      destination_path = File.join(
        (dst || File.dirname(src)),
        File.basename(src, '.gz')
      )

      FileUtils.mkdir_p File.dirname(destination_path)
      output_file = File.open(destination_path, 'wb')
      Zlib::GzipReader.open(src) do |gz|
        gz.each_line { |extract| output_file.write extract }
      end
      output_file.close
      destination_path
    rescue => error
      raise "Unable to gunzip #{src} to #{destination_path} - #{error}"
    end

    # Creates a gzip package from specified source file and removes source
    # @param (see #gunzip)
    # @return (see #gunzip)
    def gunzip!(src, dst = nil)
      output = gunzip(src, dst)
      FileUtils.rm_f src
      output
    end

    # Creates a tarball archive from specified source file or directory
    # @param src [String] Path to source file or directory
    # @param dst [String] Path to output tarball archive file
    # @param filter [String] Glob-like pattern for source file selection
    # @return [String] Absolute path to output file
    def tar(src, dst = nil, filter = '**/*')
      destination_path = dst || File.join(File.dirname(src), File.basename(src) + '.tar')

      FileUtils.mkdir_p File.dirname(destination_path)
      files = if File.file?(src)
                Dir.glob(src, File::FNM_DOTMATCH)
              else
                Dir.glob(File.join(src, '/', filter), File::FNM_DOTMATCH)
              end

      File.open(destination_path, 'wb') do |tarball|
        Gem::Package::TarWriter.new(tarball) do |tar|
          tar.mkdir '.', 16877 if files.empty?

          files.each do |file_path|
            mode = File.stat(file_path).mode
            relative_file = File.file?(src) ? File.basename(file_path) : file_path.sub((src + File::Separator).to_s, '')
            tar.mkdir(relative_file, mode) && next if File.directory?(file_path)
            tar.add_file(relative_file, mode) do |tf|
              File.open(file_path, 'rb') { |f| tf.write f.read }
            end
            Log.debug " - Adding #{relative_file} to #{destination_path}"
          end
        end
      end
      destination_path
    rescue => error
      raise "Unable to create tarball - #{error}"
    end

    # Creates a tarball package from specified source file or directory and removes source
    # @param (see #tar)
    # @return (see #tar)
    def tar!(src, dst = nil, filter = '**/*')
      tarball = tar(src, dst, filter)
      FileUtils.rm_rf src
      tarball
    end

    # Unpacks a tarball archive to a specified directory
    # @param src [String] Path to source tarball file
    # @param dst [String] Path to output directory
    # @return [String] Absolute path to output file
    def untar(src, dst = nil)
      destination_path = dst || File.dirname(src)

      # Create destination directory
      FileUtils.mkdir_p destination_path

      # Open archive for reading
      file_stream = File.open(src, 'r')
      Gem::Package::TarReader.new(file_stream) do |tar|
        tar.each do |tar_file_path|
          destination = File.join destination_path, tar_file_path.full_name

          if tar_file_path.directory?
            FileUtils.mkdir_p destination
          else
            FileUtils.mkdir_p File.dirname destination
            File.open(destination, 'wb') { |f| f.write tar_file_path.read }
          end
        end
      end
      file_stream.close
      destination_path
    end

    # Unpacks a tarball archive to a specified directory and removes source
    # @param (see #untar)
    # @return (see #untar)
    def untar!(src, dst = nil)
      result = untar(src, dst)
      FileUtils.rm_rf src
      result
    end

    # Creates gzip compresses tarball archive
    # @param (see #tar)
    # @return (see #gzip)
    def tgz(src, dst = nil, filter = '**/*')
      gzip(tar(src, nil, filter), dst)
    end

    # Creates gzip compresses tarball archive and removes source
    # @param (see #tar)
    # @return (see #gzip)
    def tgz!(src, dst = nil, filter = '**/*')
      gzip!(tar!(src, nil, filter), dst)
    end

    # Unpacks gzip compresses tarball archive
    # @param (see #gunzip)
    # @return (see #tar)
    def untgz(src, dst = nil)
      untar(gunzip(src), dst)
    end

    # Unpacks gzip compresses tarball archive and removes source
    # @param (see #gunzip)
    # @return (see #tar)
    def untgz!(src, dst = nil)
      untar!(gunzip!(src), dst)
    end
  end
end
