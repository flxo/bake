#!/usr/bin/env ruby

require 'helper'

require 'common/version'

require 'bake/options/options'
require 'common/exit_helper'

module Bake

describe "Option Parser" do

  it 'should provide a help flag with -h' do
    Bake.options = Options.new(["-h"])
    expect { Bake.options.parse_options() }.to raise_error(SystemExit)
    expect($mystring.include?("Usage:")).to be == true
    expect(ExitHelper.exit_code).to be == 0
  end
  it 'should provide a help flag with --help' do
    Bake.options = Options.new(["--help"])
    expect { Bake.options.parse_options() }.to raise_error(SystemExit)
    expect($mystring.include?("Usage:")).to be == true
    expect(ExitHelper.exit_code).to be == 0
  end

  it 'should provide an available toolchains flag' do
    Bake.options = Options.new(["--toolchain-names"])
    expect { Bake.options.parse_options() }.to raise_error(SystemExit)
    expect($mystring.include?("Available toolchains:")).to be == true
    expect($mystring.include?("Diab")).to be == true
  end

  it 'should provide a flag for printing tool options' do
    Bake.options = Options.new(["--toolchain-info"])
    expect { Bake.options.parse_options() }.to raise_error(SystemExit)
    expect($mystring.include?("Argument for option --toolchain-info missing")).to be == true

    Bake.options = Options.new(["--toolchain-info", "blah"])
    expect { Bake.options.parse_options() }.to raise_error(SystemExit)
    expect($mystring.include?("Toolchain not available")).to be == true

    Bake.options = Options.new(["--toolchain-info", "Diab"])
    expect { Bake.options.parse_options() }.to raise_error(SystemExit)
    expect($mystring.split("SOURCE_FILE_ENDINGS").length).to be == 4 # included 3 times
  end

  it 'should provide a flag to specify number of compile threads' do
    Bake.options = Options.new([])
    expect { Bake.options.parse_options() }.to raise_error(SystemExit)
    expect(Bake.options.threads).to be == 8 # default

    Bake.options = Options.new(["-j"])
    expect { Bake.options.parse_options() }.to raise_error(SystemExit)
    expect($mystring.include?("Argument for option -j missing")).to be == true

    Bake.options = Options.new(["-j", "aaaaah"])
    expect { Bake.options.parse_options() }.to raise_error(SystemExit)

    Bake.options = Options.new(["-j", "2"])
    expect { Bake.options.parse_options() }.to raise_error(SystemExit)
    expect(Bake.options.threads).to be == 2
  end

  it 'should provide a config names with default' do
    Bake.startBake("default/libD", ["--list"])
    expect($mystring.include?("* testL1A")).to be == true
    expect($mystring.include?("* testL1B (default)")).to be == true
    expect($mystring.include?("* testL1C")).to be == true
  end

  it 'should provide config names' do
    Bake.startBake("default/libNoD", ["--list"])
    expect($mystring.include?("* testL2A")).to be == true
    expect($mystring.include?("* testL2B")).to be == true
    expect($mystring.include?("* testL2C")).to be == true
  end

  it 'should provide config names with description' do
    Bake.startBake("desc/main1", ["--list"])
    expect($mystring.include?("No configuration with a DefaultToolchain found")).to be == false
    expect($mystring.include?("* test1: Bla")).to be == true
    expect($mystring.include?("* test2:")).to be == true
    expect($mystring.include?("* test3")).to be == true
    expect($mystring.include?("* test3:")).to be == false
    expect($mystring.include?("* test4 (default): Fasel")).to be == true
  end

  it 'should not provide config names' do
    Bake.startBake("desc/main2", ["--list"])
    expect($mystring.include?("* test")).to be == false
    expect($mystring.include?("No configuration with a DefaultToolchain found")).to be == true
  end

  it 'should provide a license' do
    Bake.options = Options.new(["--license"])
    expect { Bake.options.parse_options() }.to raise_error(SystemExit)
    expect($mystring.include?("E.S.R.")).to be == true
    expect($mystring.include?("lake")).to be == true
    expect($mystring.include?("cxxproject")).to be == true
  end

end

end
