#!/usr/bin/env ruby

require 'helper'

require 'common/version'

require 'bake/options/options'
require 'common/exit_helper'
require 'fileutils'

module Bake

describe "InjectDeps" do

  it 'SimpleTest' do
    Bake.startBake("injectDeps/main", ["testSimpleA", "-v3", "--debug"])

    testStr = ":\n"+
      "main,testSimpleA\n"+
      "- main,testSimpleB\n"+
      "- main,testSimpleC\n"+
      "main,testSimpleB\n"+
      "- main,testSimpleC\n"+
      "main,testSimpleC"
    expect($mystring.include?testStr).to be == true
    expect(ExitHelper.exit_code).to be == 0
  end


  it 'TwoStep' do
    Bake.startBake("injectDeps/main", ["test2StepA", "-v3", "--debug"])

    testStr = ":\n"+
      "main,test2StepA\n"+
      "- main,test2StepC\n"+
      "- main,test2StepB\n"+
      "- main,test2StepD\n"+
      "main,test2StepC\n"+
      "- main,test2StepE\n"+
      "- main,test2StepF\n"+
      "- main,test2StepC2\n"+
      "main,test2StepB\n"+
      "- main,test2StepE\n"+
      "- main,test2StepB2\n"+
      "main,test2StepD\n"+
      "- main,test2StepF\n"+
      "- main,test2StepD2\n"+
      "main,test2StepE\n"+
      "- main,test2StepB2\n"+
      "- main,test2StepC2\n"+
      "main,test2StepF\n"+
      "- main,test2StepD2\n"+
      "- main,test2StepC2\n"+
      "main,test2StepC2\n"+
      "- main,test2StepD2\n"+
      "- main,test2StepB2\n"+
      "main,test2StepB2\n"+
      "- main,test2StepD2\n"+
      "- main,test2StepC2\n"+
      "main,test2StepD2\n"+
      "- main,test2StepB2\n"+
      "- main,test2StepC2"
    expect($mystring.include?testStr).to be == true
    expect(ExitHelper.exit_code).to be == 0
  end

  it 'Circular' do
    Bake.startBake("injectDeps/main", ["testA", "-v3", "--debug"])

    testStr = ":\n"+
      "main,testA\n"+
      "- main,testB\n"+
      "- main,testC\n"+
      "- main,testF\n"+
      "main,testB\n"+
      "- main,testG\n"+
      "- main,testD\n"+
      "- main,testF\n"+
      "main,testC\n"+
      "- main,testD\n"+
      "- main,testG\n"+
      "- main,testF\n"+
      "main,testF\n"+
      "- main,testG\n"+
      "main,testD\n"+
      "- main,testG\n"+
      "- main,testE\n"+
      "- main,testF\n"+
      "main,testG\n"+
      "- main,testF\n"+
      "main,testE\n"+
      "- main,testG\n"+
      "- main,testB\n"+
      "- main,testF"
    expect($mystring.include?testStr).to be == true
    expect(ExitHelper.exit_code).to be == 0
  end

end

end
