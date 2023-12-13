$LOAD_PATH.unshift(File.expand_path("#{BASE_DIR}/lib/util"))

require 'archive'
require 'tmpdir'
require 'digest'

include Util::Archive

RSpec.describe Util::Archive do
  before(:context) do
    @test_data_dir = Dir.mktmpdir, 'pipeline_util_archive'

    # paths to test folders / files
    # aim to test single file, folder packaging and nested folders packaging / unpackaging operations

    @single_file_path = File.join @test_data_dir, 'single-file', 'file.txt'
    FileUtils.mkdir_p File.dirname @single_file_path
    fill_random_file_content @single_file_path

    @single_file_no_extension_path = File.join (File.dirname @single_file_path), 'file'
    fill_random_file_content @single_file_no_extension_path

    @single_folder_path = File.join @test_data_dir, 'single-folder'
    FileUtils.mkdir_p @single_folder_path
    fill_random_folder_content @single_folder_path, false

    @nested_folder_path = File.join @test_data_dir, 'nested-folder'
    FileUtils.mkdir_p @nested_folder_path
    fill_random_folder_content @nested_folder_path, true, 2

    @nested_folder_dots_path = File.join @test_data_dir, 'nested-folder-dots'
    FileUtils.mkdir_p @nested_folder_dots_path
    fill_random_folder_content @nested_folder_dots_path, true, 2, true

    @empty_folder_path = File.join @test_data_dir, 'empty-folder'
    FileUtils.mkdir_p @empty_folder_path

    @tmp_folder = File.join @test_data_dir, 'temp'
  end

  context '.gzip' do
    it 'gunzip throws exception' do
      expect {
        gunzip('~/file-which-does-not-exits')
      }.to raise_exception(/Unable to gunzip/)
    end

    it 'gzip! removes original file' do
      src_file_path = File.join(@test_data_dir, generate_random_file_name('txt'))

      File.open(src_file_path, 'w') do |file|
        file.puts 'text content'
      end

      dst_packed_file_path = File.join(@test_data_dir, generate_random_file_name('gzip'))

      gzip!(src_file_path, dst_packed_file_path)

      # expecting deletion of the original file
      expect(File.file?(dst_packed_file_path)).to be(true)
      expect(File.file?(src_file_path)).to be(false)
    end

    it 'gzip a single file' do
      src_file_path = @single_file_path
      dst_packed_file_path = File.join(@tmp_folder, generate_random_file_name('gzip'))

      gz = gzip(src_file_path, dst_packed_file_path)
      expect(File.file?(gz)).to be(true)
    end

    it 'gzip a single file with no extension' do
      src_file_path = @single_file_no_extension_path
      dst_packed_file_path = File.join(@tmp_folder, generate_random_file_name('gzip'))

      gz = gzip(src_file_path, dst_packed_file_path)
      expect(File.file?(gz)).to be(true)
    end

    it 'gzip a single file to non-existing folder' do
      src_file_path = @single_file_path
      # cause PkgTools has to handle non-existing folders
      dst_packed_file_path = File.join(@tmp_folder, generate_random_folder_name, generate_random_file_name('gzip'))

      gz = gzip(src_file_path, dst_packed_file_path)
      expect(File.file?(gz)).to be(true)
    end
  end

  context '.tgz' do
    it 'tgz! removes original file' do
      src_file_path = File.join(@test_data_dir, generate_random_file_name('txt'))

      File.open(src_file_path, 'w') do |file|
        file.puts 'text content'
      end

      dst_packed_file_path = File.join(@test_data_dir, generate_random_file_name('gzip'))

      tgz!(src_file_path, dst_packed_file_path)

      # expecting deletion of the original file
      expect(File.file?(dst_packed_file_path)).to be(true)
      expect(File.file?(src_file_path)).to be(false)
    end

    it 'untgz! removes original file' do
      src_file_path = File.join(@test_data_dir, generate_random_file_name('txt'))
      dst_folder_path = File.join(@test_data_dir, generate_random_folder_name)

      File.open(src_file_path, 'w') do |file|
        file.puts 'text content'
      end

      dst_packed_file_path = File.join(@test_data_dir, generate_random_file_name('gz'))

      tgz(src_file_path, dst_packed_file_path)
      untgz!(dst_packed_file_path, dst_folder_path)

      # expecting deletion of the original file
      expect(File.file?(dst_packed_file_path)).to be(false)
    end
  end

  context '.tar' do
    it 'tar! removes original file' do
      src_file_path = File.join(@test_data_dir, generate_random_file_name('txt'))

      File.open(src_file_path, 'w') do |file|
        file.puts 'text content'
      end

      dst_packed_file_path = File.join(@test_data_dir, generate_random_file_name('gzip'))

      tar!(src_file_path, dst_packed_file_path)

      # expecting deletion of the original file
      expect(File.file?(dst_packed_file_path)).to be(true)
      expect(File.file?(src_file_path)).to be(false)
    end

    it 'tar throws exception' do
      expect {
        # would raise an exception while writing to existing directory
        tar('~/file-which-does-not-exits', @test_data_dir)
      }.to raise_exception(/Unable to create tarball/)
    end

    it 'tar a single file' do
      src_file_path = @single_file_path
      dst_packed_file_path = File.join(@tmp_folder, generate_random_file_name('tar'))
      tar = tar src_file_path, dst_packed_file_path
      expect(File.file?(tar)).to be(true)
    end

    it 'tar a single file to non-existing folder' do
      src_file_path = @single_file_path
      dst_packed_file_path = File.join(@tmp_folder, generate_random_folder_name, generate_random_file_name('tar'))

      tar = tar src_file_path, dst_packed_file_path
      expect(File.file?(tar)).to be(true)
    end
    it 'tar an empty folder' do
      dst_packed_file_path = File.join(@tmp_folder, generate_random_file_name('tar'))
      dst_unpacked_folder_path = File.join(@tmp_folder, generate_random_folder_name)

      # src_folder_path =
      src_folder_path = FileUtils.mkdir_p(generate_random_folder_path).first

      # can pack?
      Log.debug "Packing tar folder: #{src_folder_path} to #{dst_packed_file_path}"
      tar = tar(src_folder_path, dst_packed_file_path)
      expect(File.file? tar).to be(true)

      # # can unpack?
      Log.debug "Unpacking tar folder: #{dst_packed_file_path} to #{dst_unpacked_folder_path}"
      untar(dst_packed_file_path, dst_unpacked_folder_path)

      # check folder structure - amount of files, folder, and its content
      expect(File.exist? dst_unpacked_folder_path).to be(true)
      expect_same_folder_content(src_folder_path, dst_unpacked_folder_path, '*', true)

      # # expect zero files
      all_unpacked_file_paths = Dir[File.join(dst_unpacked_folder_path, '*')]
      expect(all_unpacked_file_paths.length).to be(0)
    end

    it 'tar a single folder' do
      dst_packed_file_path = File.join(@tmp_folder, generate_random_file_name('tar'))
      dst_unpacked_folder_path = File.join(@tmp_folder, generate_random_folder_name)

      src_folder_path = @single_folder_path

      # can pack?
      Log.debug "Packing tar folder: #{src_folder_path} to #{dst_packed_file_path}"
      tar src_folder_path, dst_packed_file_path
      expect(File.file?(dst_packed_file_path)).to be(true)

      # can unpack?
      Log.debug "Unpacking tar folder: #{dst_packed_file_path} to #{dst_unpacked_folder_path}"
      untar dst_packed_file_path, dst_unpacked_folder_path

      # check folder structure - amount of files, folder, and its content
      expect_same_folder_content(src_folder_path, dst_unpacked_folder_path)
    end

    it 'tar a nested folder' do
      src_folder_path = @nested_folder_path

      dst_packed_file_path = File.join(@tmp_folder, generate_random_file_name('tar'))
      dst_unpacked_folder_path = File.join(@tmp_folder, generate_random_folder_name)

      # can pack?
      Log.debug "Packing nested tar folder: #{src_folder_path} to #{dst_packed_file_path}"
      tar(src_folder_path, dst_packed_file_path)
      expect(File.file?(dst_packed_file_path)).to be(true)

      # can unpack?
      Log.debug "Unpacking tar folder: #{dst_packed_file_path} to #{dst_unpacked_folder_path}"
      untar(dst_packed_file_path, dst_unpacked_folder_path)

      # check folder structure - amount of files, folder, and its content
      expect_same_folder_content(src_folder_path, dst_unpacked_folder_path)
    end

    it 'tar a nested folder - **/*.yaml files' do
      src_files_extension = '**/*.yaml'

      dst_packed_file_path = File.join(@tmp_folder, generate_random_file_name('tar'))
      dst_unpacked_folder_path = File.join(@tmp_folder, generate_random_folder_name)

      # can pack?
      Log.debug "Packing nested tar folder with extension:[#{src_files_extension}]: #{@nested_folder_path} to #{dst_packed_file_path}"
      tar(@nested_folder_path, dst_packed_file_path, src_files_extension)
      expect(File.file?(dst_packed_file_path)).to be(true)

      # can unpack?
      Log.debug "Unpacking tar folder: #{dst_packed_file_path} to #{dst_unpacked_folder_path}"
      untar(dst_packed_file_path, dst_unpacked_folder_path)

      # check folder structure - amount of files, folder, and its content
      expect_same_folder_content(@nested_folder_path, dst_unpacked_folder_path, src_files_extension)
    end

    it 'tar a nested folder - *.yaml files' do
      src_files_extension = '*.yaml'

      dst_packed_file_path = File.join(@tmp_folder, generate_random_file_name('tar'))
      dst_unpacked_folder_path = File.join(@tmp_folder, generate_random_folder_name)

      # can pack?
      Log.debug "Packing nested tar folder with extension:[#{src_files_extension}]: #{@nested_folder_path} to #{dst_packed_file_path}"
      tar(@nested_folder_path, dst_packed_file_path, src_files_extension)
      expect(File.file?(dst_packed_file_path)).to be(true)

      # can unpack?
      Log.debug "Unpacking tar folder: #{dst_packed_file_path} to #{dst_unpacked_folder_path}"
      untar(dst_packed_file_path, dst_unpacked_folder_path)

      # check folder structure - amount of files, folder, and its content
      expect_same_folder_content(@nested_folder_path, dst_unpacked_folder_path, src_files_extension, true)
    end

    it 'tar a nested folder dot files' do
      dst_packed_file_path = File.join(@tmp_folder, generate_random_file_name('tar'))
      dst_unpacked_folder_path = File.join(@tmp_folder, generate_random_folder_name)

      # can pack?
      Log.debug "Packing tar folder #{@nested_folder_dots_path} to #{dst_packed_file_path}"
      tar(@nested_folder_dots_path, dst_packed_file_path)
      expect(File.file?(dst_packed_file_path)).to be(true)

      # can unpack?
      Log.debug "Unpacking tar folder: #{dst_packed_file_path} to #{dst_unpacked_folder_path}"
      untar(dst_packed_file_path, dst_unpacked_folder_path)

      # check folder structure - amount of files, folder, and its content
      expect_same_folder_content(@nested_folder_dots_path, dst_unpacked_folder_path, '*', true)
    end
  end

  context '.gzip and tar' do
    it 'gzip and tar empty folder' do
      src_file_path = @empty_folder_path
      gz = tgz(src_file_path, File.join(@tmp_folder, generate_random_file_name('tar.gz')))
      expect(File.file?(gz)).to be(true)

      utgz = untgz(gz, File.join(@tmp_folder, generate_random_folder_name))
      expect_same_folder_content(src_file_path, utgz, "*", true)
    end

    it 'gzip and tar nested folder' do
      src_file_path = @nested_folder_path
      gz = tgz(src_file_path)
      expect(File.file?(gz)).to be(true)

      utgz = untgz(gz, File.join(@tmp_folder, generate_random_folder_name))
      expect_same_folder_content(src_file_path, utgz)
    end

    it 'gzip and tar nested folder - only yaml' do
      src_file_path = @nested_folder_path
      gz = tgz(src_file_path, nil, '*.yaml')
      expect(File.file?(gz)).to be(true)

      utgz = untgz(gz, File.join(@tmp_folder, generate_random_folder_name))
      expect_same_folder_content(src_file_path, utgz, '*.yaml')
    end

    it 'untar! gunzip!' do
      src_file_path = @nested_folder_path
      gz = tgz(src_file_path, nil)
      expect(File.file?(gz)).to be(true)

      dstFolderPath = generate_random_folder_path
      utgz = untar! gunzip!(gz), dstFolderPath

      expect_same_folder_content(src_file_path, utgz)
    end
  end

  private

  def fill_random_folder_content(folder_path, generate_folders = true, nest_level = 1, dot_content = false)
    if (nest_level < 0)
      return
    end

    folders_count = rand(1..2)
    files_count = rand(1..2)

    (0..files_count).each do
      fill_random_file_content File.join(folder_path, generate_random_file_name)
      fill_random_file_content File.join(folder_path, (generate_random_file_name 'yaml'))
    end

    if (generate_folders)

      (0..folders_count).each do
        random_folder_path = File.join(folder_path, generate_random_folder_name)
        FileUtils.mkdir_p random_folder_path
        fill_random_folder_content random_folder_path, generate_folders, (nest_level - 1)
      end
    end

    if dot_content
      (0..folders_count).each do
        random_folder_path = File.join(folder_path, '.' + generate_random_folder_name)
        FileUtils.mkdir_p random_folder_path
        fill_random_folder_content random_folder_path, generate_folders, (nest_level - 1)
      end

      (0..files_count).each do
        fill_random_file_content File.join(folder_path, '.' + generate_random_file_name)
        fill_random_file_content File.join(folder_path, '.' + (generate_random_file_name 'yaml'))
      end
    end
  end

  def fill_random_file_content(file_path)
    lines_count = rand(2...3)

    File.open(file_path, 'w') do |file|
      (0..lines_count).each do
        file.puts rnd_string
      end
    end
  end

  def rnd_string
    Array.new(32) { rand(36).to_s(36) }.join
  end

  def generate_random_file_name(file_ext = '.txt')
    if file_ext.start_with?('.')
      rnd_string + file_ext
    else
      rnd_string + '.' + file_ext
    end
  end

  def generate_random_folder_name
    rnd_string
  end

  def generate_random_folder_path
    File.join(@tmp_folder, rnd_string)
  end

  def expect_same_md5(src_file, dst_file)
    src_md5 = Digest::MD5.hexdigest (File.read src_file)
    unpacked_md5 = Digest::MD5.hexdigest (File.read dst_file)

    Log.debug("src:#{src_md5} dst:#{unpacked_md5}")

    expect(src_md5).to eq(unpacked_md5)
  end

  def expect_same_folder_content(src_folder_path,
                                 dst_unpacked_folder_path,
                                 src_files_extension = '*',
                                 allowEmptyFolder = false)

    src_filter_exp = File.join(src_folder_path, '/', src_files_extension)
    dst_filter_exp = File.join(dst_unpacked_folder_path, '/', src_files_extension)

    # should be the same amount of files
    all_src_entries = Dir[src_filter_exp]
    all_dst_entries = Dir[dst_filter_exp]

    all_src_file_paths = all_src_entries.select { |f| File.file?(f) }
    all_unpacked_file_paths = all_dst_entries.select { |f| File.file?(f) }

    all_src_folder_paths = Dir[src_filter_exp].map { |k, v| File.dirname k }.uniq { |f| f }
    all_unpacked_folder_paths = Dir[dst_filter_exp].map { |k, v| File.dirname k }.uniq { |f| f }

    relative_src_folder = src_folder_path
    relative_dst_folder = dst_unpacked_folder_path

    Log.debug "Checking src path:#{src_folder_path}"
    Log.debug "Checking dst path:#{dst_unpacked_folder_path}"

    # expecting one or more files/folders in the src folder unless we test empty folder packaging
    unless allowEmptyFolder
      expect(all_src_file_paths.length).to be > 0
      expect(all_src_folder_paths.length).to be > 0
    end

    Log.debug "Checking total files count: #{all_src_file_paths.length} with expected #{all_unpacked_file_paths.length}"
    expect(all_src_file_paths.length).to be(all_unpacked_file_paths.length)

    Log.debug "Checking total folders count: #{all_src_folder_paths.length} with expected #{all_unpacked_folder_paths.length}"
    expect(all_src_folder_paths.length).to be(all_unpacked_folder_paths.length)

    # all file match names and md5
    all_src_file_paths.each do |src_file_path|
      # unpacked file exists
      relative_source_file_path = src_file_path.sub relative_src_folder, ''
      expected_dst_file_path = File.join(relative_dst_folder, relative_source_file_path)

      # file-folder checks
      if File.file?(expected_dst_file_path)
        Log.debug "Checking file exists: #{relative_source_file_path} with expected #{expected_dst_file_path}"
        expect(File.file?(expected_dst_file_path)).to be(true)

        Log.debug "Checking content md5: #{src_file_path} with #{expected_dst_file_path}"
        expect_same_md5(src_file_path, expected_dst_file_path)
      else
        Log.debug "Checking folder exists: #{relative_source_file_path} with expected #{expected_dst_file_path}"
        expect(File.directory?(expected_dst_file_path)).to be(true)
      end
    end
  end

  def gzip_single_file_to_folder(src_file_path, dst_packed_file_path)
    dst_packed_file_path = dst_packed_file_path
    dst_unpacked_file_path = File.join(@tmp_folder, generate_random_file_name('gzip'))

    # can pack?
    Log.debug "Packing gzip file: #{src_file_path} to #{dst_packed_file_path}"
    @pkg_service.gzip(src_file_path, dst_packed_file_path)
    expect(File.file?(dst_packed_file_path)).to be(true)

    # can unpack?
    Log.debug "Unpacking gzip file: #{dst_packed_file_path} to #{dst_unpacked_file_path}"
    @pkg_service.ungzip(dst_packed_file_path, dst_unpacked_file_path)
    expect(File.file?(dst_unpacked_file_path)).to be(true)

    # is content same-same?
    # we don't want to break actual files between packing/unpacking routines
    Log.debug "Checking gzip content md5: #{src_file_path} to #{dst_unpacked_file_path}"
    expect_same_md5(src_file_path, dst_unpacked_file_path)
  end

  def tag_single_file_to_folder(src_file_path, dst_packed_file_path)
    dst_unpacked_folder_path = File.join(@tmp_folder, generate_random_folder_name)

    # can pack?
    Log.debug "Packing tar file: #{src_file_path} to #{dst_packed_file_path}"
    @pkg_service.tar(src_file_path, dst_packed_file_path)
    expect(File.file?(dst_packed_file_path)).to be(true)

    # can unpack?
    Log.debug "Unpacking tar file: #{dst_packed_file_path} to #{dst_unpacked_folder_path}"
    @pkg_service.untar(dst_packed_file_path, dst_unpacked_folder_path)

    # should be one file
    all_unpacked_file_paths = Dir[File.join(dst_unpacked_folder_path, '*')]
    expect(all_unpacked_file_paths.length).to be(1)

    # that file should exist
    dst_unpacked_file_path = all_unpacked_file_paths[0]
    expect(File.file?(dst_unpacked_file_path)).to be(true)

    # is content same-same?
    # we don't want to break actual files between packing/unpacking routines
    Log.debug "Checking gzip content md5: #{src_file_path} with #{dst_unpacked_file_path}"
    expect_same_md5(src_file_path, dst_unpacked_file_path)
  end

  def gzip_with_tar_to_folder(src_file_or_folder_path, src_file_extension = '*.*')
    src_file_path = src_file_or_folder_path

    dst_packed_gzip_file_path = File.join(@tmp_folder, generate_random_file_name('tar.gz'))
    gzip_filename = File.basename(dst_packed_gzip_file_path, File.extname(dst_packed_gzip_file_path))

    dst_unpacked_gzip_file_path = File.join(@tmp_folder, generate_random_folder_name, gzip_filename + '.tar')
    dst_unpacked_tar_folder_path = File.join(@tmp_folder, generate_random_folder_name)

    # can pack?
    Log.debug "Packing gzip(tar) for nested folder: #{src_file_path} to #{dst_packed_gzip_file_path}"
    @pkg_service.gzip_with_tar(src_file_path, dst_packed_gzip_file_path, src_file_extension)

    # can unzip? it should be tar-file with the same name
    Log.debug "ungzip gzip(tar) for nested folder: #{dst_packed_gzip_file_path} to #{dst_unpacked_gzip_file_path}"
    @pkg_service.ungzip(dst_packed_gzip_file_path, dst_unpacked_gzip_file_path)

    # tar's expectations
    tar_file_name = File.basename dst_unpacked_gzip_file_path
    tar_file_extension = File.extname dst_unpacked_gzip_file_path

    expected_tar_filename = File.basename(dst_packed_gzip_file_path, File.extname(dst_packed_gzip_file_path)) + '.tar'

    expect(tar_file_name).to eq(expected_tar_filename)
    expect(tar_file_extension).to eq('.tar')

    Log.debug "untar gzip(tar) for nested folder: #{dst_unpacked_gzip_file_path} to #{dst_unpacked_tar_folder_path}"
    @pkg_service.untar(dst_unpacked_gzip_file_path, dst_unpacked_tar_folder_path)

    # check folder structure - amount of files, folder, and its content
    expect_same_folder_content(src_file_path, dst_unpacked_tar_folder_path, src_file_extension)
  end
end # RSpec.describe
