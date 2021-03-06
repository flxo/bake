#!/usr/bin/env ruby

require 'helper'

require 'common/version'

require 'bake/options/options'
require 'bake/util'
require 'common/exit_helper'
require 'socket'
require 'fileutils'

require 'common/ext/stdout'

module Bake

describe "Makefile" do

  it 'builds' do
    Bake.startBake("make/main", ["test"])
    expect($mystring.include?("make all")).to be == true
    expect($mystring.include?("Building done.")).to be == true
  end

  it 'cleans' do
    Bake.startBake("make/main",  ["test", "-c"])
    expect($mystring.include?("Cleaning done.")).to be == true
  end

  it 'cleanStep build' do
    Bake.startBake("make/main",  ["test_cleanstep"])
    expect($mystring.include?("make clean")).to be == false
  end

  it 'cleanStep clean' do
    Bake.startBake("make/main",  ["test_cleanstep", "-c"])
    expect($mystring.include?("make clean")).to be == true
  end

end

end
