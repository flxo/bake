#!/usr/bin/env ruby


require 'bake/model/metamodel_ext'

require 'bake/util'
require 'bake/cache'
require 'bake/subst'
require 'bake/mergeConfig'

require 'common/exit_helper'
require 'common/ide_interface'
require 'common/ext/file'
require 'bake/toolchain/provider'
require 'common/ext/stdout'
require 'common/utils'
require 'bake/toolchain/colorizing_formatter'
require 'bake/config/loader'

require 'blocks/block'
require 'blocks/commandLine'
require 'blocks/makefile'
require 'blocks/compile'
require 'blocks/convert'
require 'blocks/library'
require 'blocks/executable'
require 'blocks/docu'

require 'set'
require 'socket'

require 'blocks/showIncludes'
require 'common/abortException'

require 'adapt/config/loader'
require "thwait"

module Bake

  class SystemCommandFailed < Exception
  end

  class ToCxx

    @@linkBlock = 0

    def self.linkBlock
      @@linkBlock = 1
    end

    def initialize
      @configTcMap = {}
    end

    def createBaseTcsForConfig
      @referencedConfigs.each do |projName, configs|
        configs.each do |config|
          tcs = Utils.deep_copy(@defaultToolchain)
          @configTcMap[config] = tcs
        end
      end
    end

    def createTcsForConfig
      @referencedConfigs.each do |projName, configs|
        configs.each do |config|
          integrateToolchain(@configTcMap[config], config.toolchain)
        end
      end
    end

    def substVars
      Subst.itute(@mainConfig, Bake.options.main_project_name, true, @configTcMap[@mainConfig], @referencedConfigs, @configTcMap)
      @referencedConfigs.each do |projName, configs|
        configs.each do |config|
          if config != @mainConfig
            Subst.itute(config, projName, false, @configTcMap[config], @referencedConfigs, @configTcMap)
          end
        end
      end
      Subst.resolveOutputDir
    end

    def addLib(block, configSteps)
      Array(configSteps.step).each do |step|
        if Bake::Metamodel::Makefile === step
          block.lib_elements << LibElement.new(LibElement::LIB_WITH_PATH, step.lib) if step.lib != ""
        end
      end if configSteps
    end

    def addSteps(block, blockSteps, configSteps)
      Array(configSteps.step).each do |step|
        if Bake::Metamodel::Makefile === step
          blockSteps << Blocks::Makefile.new(step, @referencedConfigs, block)
        elsif Bake::Metamodel::CommandLine === step
          blockSteps << Blocks::CommandLine.new(step, @referencedConfigs)
        end
      end if configSteps
    end

    def addDependencies(block, config)
      config.dependency.each do |dep|
        @referencedConfigs[dep.name].each do |configRef|
          if configRef.name == dep.config

            if configRef.private && configRef.parent.name != config.parent.name
              Bake.formatter.printError("#{config.parent.name} (#{config.name}) depends on #{configRef.parent.name} (#{configRef.name}) which is private.", configRef)
              ExitHelper.exit(1)
            end

            block.dependencies << configRef.qname if not Bake.options.project# and not Bake.options.filename
            blockRef = Blocks::ALL_BLOCKS[configRef.qname]
            block.childs << blockRef
            block.depToBlock[dep.name + "," + dep.config] = blockRef
            blockRef.parents << block
            break
          end
        end
      end
    end

    def calcPrebuildBlocks
      @referencedConfigs.each do |projName, configs|
        configs.each do |config|
          if config.prebuild
            @prebuild ||= {}
            config.prebuild.except.each do |except|
              pName = projName
              if not except.name.empty?
                if not @referencedConfigs.keys.include? except.name
                  Bake.formatter.printWarning("Warning: prebuild project #{except.name} not found")
                  next
                end
                pName = except.name
              end
              if except.config != "" && !@referencedConfigs[pName].any? {|config| config.name == except.config}
                Bake.formatter.printWarning("Warning: prebuild config #{except.config} of project #{pName} not found")
                next
              end

              if not @prebuild.include?pName
                @prebuild[pName] = [except.config]
              else
                @prebuild[pName] << except.config
              end
            end
          end
        end
      end
    end

    def makeBlocks
      @referencedConfigs.each do |projName, configs|
        configs.each do |config|

          prebuild = !@prebuild.nil?
          if @prebuild and @prebuild.has_key?projName
            prebuild = false if (@prebuild[projName].include?"" or @prebuild[projName].include?config.name)
          end

          block = Blocks::Block.new(config, @referencedConfigs, prebuild, @configTcMap[config])
          Blocks::ALL_BLOCKS[config.qname] = block
        end
      end
    end

    def makeGraph
      @referencedConfigs.each do |projName, configs|
        configs.each do |config|
          block = Blocks::ALL_BLOCKS[config.qname]
            addDependencies(block, config)
        end
      end
      Blocks::ALL_BLOCKS.each do |name,block|
        block.dependencies.uniq!
        block.childs.uniq!
        block.parents.uniq!
      end


      # inject dependencies
      num_interations = 0
      begin
        if (num_interations > 0) and Bake.options.debug and Bake.options.verbose >= 3
          puts "Inject dependencies, iteration #{num_interations}:"
          Blocks::ALL_BLOCKS.each do |name,block|
            puts block.config.qname
            block.dependencies.each { |d| puts "- #{d}" }
          end
        end

        counter = 0
        Blocks::ALL_BLOCKS.each do |name,block|
          block.getBlocks(:parents).each do |b|
            b.config.dependency.each do |d|
              next if d.inject == ""

              dqname = "#{d.name},#{d.config}"
              dblock = Blocks::ALL_BLOCKS[dqname]
              next if name == dqname
              next if block.childs.include? dblock
              counter += 1
              newD = MergeConfig::cloneModelElement(d)
              newD.setInject("")
              ls = block.config.getBaseElement
              dblock.parents << block

              if d.inject == "front"
                block.config.setBaseElement(ls.unshift(newD))
                block.childs.unshift dblock
                block.dependencies.unshift dqname if not Bake.options.project
              else
                block.config.setBaseElement(ls + [newD])
                block.childs << dblock
                block.dependencies << dqname if not Bake.options.project
              end
              block.depToBlock[d.name + "," + d.config] = dblock

            end
          end
        end
        num_interations += 1
      end while counter > 0
    end

    def makeDot

        File.open(Bake.options.dot, 'w') do |file|
          puts "Creating #{Bake.options.dot}"

          file.write "# Generated by bake\n"
          file.write "# Example to show the graph: dot #{Bake.options.dot} -Tpng -o out.png\n"
          file.write "# Example to reduce the graph: tred #{Bake.options.dot} | dot -Tpng -o out.png\n\n"

          file.write "digraph \"#{Bake.options.main_project_name}_#{Bake.options.build_config}\" {\n\n"

          file.write "  concentrate = true\n\n"

          onlyProjectName = nil
          onlyConfigName = nil
          if Bake.options.project
            splitted = Bake.options.project.split(',')
            onlyProjectName = splitted[0]
            onlyConfigName = splitted[1] if splitted.length == 2
          end

          if onlyProjectName
            if not @referencedConfigs.include? onlyProjectName
              Bake.formatter.printError("Error: project #{onlyProjectName} not found")
              ExitHelper.exit(1)
            end
            if onlyConfigName
              if not @referencedConfigs[onlyProjectName].any? {|c| c.name == onlyConfigName}
                Bake.formatter.printError("Error: project #{onlyProjectName} with config #{onlyConfigName} not found")
                ExitHelper.exit(1)
              end
            end
          end

          foundProjs = {}
          @referencedConfigs.each do |projName, configs|
            configs.each do |config|
              config.dependency.each do |d|
                if onlyProjectName
                  next if config.parent.name != onlyProjectName && d.name != onlyProjectName
                  if onlyConfigName
                    leftSide  = config.name        == onlyConfigName && config.parent.name == onlyProjectName
                    rightSide = d.config           == onlyConfigName && d.name             == onlyProjectName
                    next if not leftSide and not rightSide
                  end
                end
                file.write "  \"#{config.qname}\" -> \"#{d.name},#{d.config}\"\n"

                foundProjs[config.parent.name] = []           if not foundProjs.include? config.parent.name
                foundProjs[config.parent.name] << config.name if not foundProjs[config.parent.name].include? config.name
                foundProjs[d.name] = []        if not foundProjs.include? d.name
                foundProjs[d.name] << d.config if not foundProjs[config.parent.name].include? d.config
              end
            end
          end
          file.write "\n"

          @referencedConfigs.each do |projName, configs|
            next if Bake.options.project and not foundProjs.include?projName
            file.write "  subgraph \"cluster_#{projName}\" {\n"
            file.write "    label =\"#{projName}\"\n"
            configs.each do |config|
              next if Bake.options.project and not foundProjs[projName].include? config.name
              file.write "    \"#{projName},#{config.name}\" [label = \"#{config.name}\", style =  filled, fillcolor = #{config.color}]\n"
            end
            file.write "  }\n\n"
          end

          file.write "}\n"
        end

        ExitHelper.exit(0)
    end

    def convert2bb
      @referencedConfigs.each do |projName, configs|
        configs.each do |config|
          block = Blocks::ALL_BLOCKS[config.qname]

          addSteps(block, block.startupSteps,  config.startupSteps)
          addSteps(block, block.exitSteps,  config.exitSteps)

          if not Bake.options.prepro and not Bake.options.conversion_info and not Bake.options.docu and not Bake.options.filename and not Bake.options.analyze
            if block.prebuild
              addLib(block, config.preSteps)
              addLib(block, config.postSteps)
              addLib(block, config.cleanSteps)
            else
              addSteps(block, block.preSteps,   config.preSteps)
              addSteps(block, block.postSteps,  config.postSteps)
              addSteps(block, block.cleanSteps, config.cleanSteps)
            end
          end

          if Bake.options.docu
            block.mainSteps << Blocks::Docu.new(config, @configTcMap[config]) unless block.prebuild
          elsif Metamodel::CustomConfig === config
            if not Bake.options.prepro and not Bake.options.conversion_info and not Bake.options.docu and not Bake.options.filename and not Bake.options.analyze
              if block.prebuild
                addLib(block, config)
              else
                addSteps(block, block.mainSteps, config) if config.step
              end
            end
          elsif Bake.options.conversion_info
            block.mainSteps << Blocks::Convert.new(block, config, @referencedConfigs) unless block.prebuild
          else
            if not block.prebuild
              compile = Blocks::Compile.new(block, config, @referencedConfigs)
              (Blocks::ALL_COMPILE_BLOCKS[projName] ||= []) << compile
              block.mainSteps << compile
            end
            if not Bake.options.filename and not Bake.options.analyze
              if Metamodel::LibraryConfig === config
                block.mainSteps << Blocks::Library.new(block, config, @referencedConfigs, compile)
              else
                block.mainSteps << Blocks::Executable.new(block, config, @referencedConfigs, compile) unless block.prebuild
              end
            end
          end



        end
      end
    end

    def callBlock(block, method)
      begin
        return block.send(method)
      rescue AbortException
        raise
      rescue Exception => ex
        if Bake.options.debug
          puts ex.message
          puts ex.backtrace
        end
        return false
      end
    end

    def callBlocks(startBlocks, method, ignoreStopOnFirstError = false)
      Blocks::ALL_BLOCKS.each {|name,block| block.visited = false; block.result = true;  block.inDeps = false }
      Blocks::Block.reset_block_counter
      result = true
      startBlocks.each do |block|
        begin
          result = callBlock(block, method) && result
        ensure
          Blocks::Block::waitForAllThreads()
          result &&= Blocks::Block.delayed_result
        end
        if not ignoreStopOnFirstError
          return false if not result and Bake.options.stopOnFirstError
        end
      end
      return result
    end

    def calcStartBlocks
      startProjectName = nil
      startConfigName = nil
      if Bake.options.project
        splitted = Bake.options.project.split(',')
        startProjectName = splitted[0]
        startConfigName = splitted[1] if splitted.length == 2
      end

      if startConfigName
        blockName = startProjectName+","+startConfigName
        if not Blocks::ALL_BLOCKS.include?(startProjectName+","+startConfigName)
          Bake.formatter.printError("Error: project #{startProjectName} with config #{startConfigName} not found")
          ExitHelper.exit(1)
        end
        startBlocks = [Blocks::ALL_BLOCKS[startProjectName+","+startConfigName]]
        Blocks::Block.set_num_projects(startBlocks)
      elsif startProjectName
        startBlocks = []
        Blocks::ALL_BLOCKS.each do |blockName, block|
          if blockName.start_with?(startProjectName + ",")
            startBlocks << block
          end
        end
        if startBlocks.length == 0
          Bake.formatter.printError("Error: project #{startProjectName} not found")
          ExitHelper.exit(1)
        end
        startBlocks.reverse! # most probably the order of dependencies if any
        Blocks::Block.set_num_projects(startBlocks)
      else
        startBlocks = [Blocks::ALL_BLOCKS[Bake.options.main_project_name+","+Bake.options.build_config]]
        Blocks::Block.set_num_projects(Blocks::ALL_BLOCKS.values)
      end
     return startBlocks
    end

    def doit()

      if Bake.options.show_includes or Bake.options.show_includes_and_defines
        s = StringIO.new
        tmp = Thread.current[:stdout]
        Thread.current[:stdout] = s unless tmp
      end

      taskType = "Building"
      if Bake.options.conversion_info
        taskType = "Showing conversion infos"
      elsif Bake.options.docu
        taskType = "Generating documentation"
      elsif Bake.options.prepro
        taskType = "Preprocessing"
      elsif Bake.options.linkOnly
          taskType = "Linking"
      elsif Bake.options.rebuild
        taskType = "Rebuilding"
      elsif Bake.options.clean
        taskType = "Cleaning"
      end

      begin

        if Bake.options.showConfigs
          al = AdaptConfig.new
          adaptConfigs = al.load()
          Config.new.printConfigs(adaptConfigs)
        else
          cache = CacheAccess.new()
          @referencedConfigs = cache.load_cache unless Bake.options.nocache

          if @referencedConfigs.nil?
            al = AdaptConfig.new
            adaptConfigs = al.load()

            @loadedConfig = Config.new
            @referencedConfigs = @loadedConfig.load(adaptConfigs)

            cache.write_cache(@referencedConfigs, adaptConfigs)
          end
        end

        taskType = "Analyzing" if Bake.options.analyze

        @mainConfig = @referencedConfigs[Bake.options.main_project_name].select { |c| c.name == Bake.options.build_config }.first

        basedOn =  @mainConfig.defaultToolchain.basedOn
        basedOnToolchain = Bake::Toolchain::Provider[basedOn]
        if basedOnToolchain.nil?
          Bake.formatter.printError("DefaultToolchain based on unknown compiler '#{basedOn}'", @mainConfig.defaultToolchain)
          ExitHelper.exit(1)
        end

        # The flag "-FS" must only be set for VS2013 and above
        ENV["MSVC_FORCE_SYNC_PDB_WRITES"] = ""
        if basedOn == "MSVC"
          begin
            res = `cl.exe 2>&1`
            raise Exception.new unless $?.success?
            scan_res = res.scan(/ersion (\d+).(\d+).(\d+)/)
            if scan_res.length > 0
              ENV["MSVC_FORCE_SYNC_PDB_WRITES"] = "-FS" if scan_res[0][0].to_i >= 18 # 18 is the compiler major version in VS2013
            else
              Bake.formatter.printError("Could not read MSVC version")
              ExitHelper.exit(1)
            end
          rescue SystemExit
            raise
          rescue Exception => e
            Bake.formatter.printError("Could not detect MSVC compiler")
            ExitHelper.exit(1)
          end
        end

        @defaultToolchain = Utils.deep_copy(basedOnToolchain)
        Bake.options.envToolchain = true if (basedOn.include?"_ENV")

        integrateToolchain(@defaultToolchain, @mainConfig.defaultToolchain)

        # todo: cleanup this hack
        Bake.options.analyze = @defaultToolchain[:COMPILER][:CPP][:COMPILE_FLAGS].include?"analyze"
        Bake.options.eclipseOrder = @mainConfig.defaultToolchain.eclipseOrder

        createBaseTcsForConfig
        substVars
        createTcsForConfig

        @@linkBlock = 0

        @prebuild = nil
        calcPrebuildBlocks if Bake.options.prebuild

        makeBlocks
        makeGraph
        makeDot if Bake.options.dot

        convert2bb

        if Bake.options.show_includes
          Thread.current[:stdout] = tmp
          Blocks::Show.includes
        end

        if Bake.options.show_includes_and_defines
          Thread.current[:stdout] = tmp
          Blocks::Show.includesAndDefines(@mainConfig, @configTcMap[@mainConfig])
        end

        startBlocks = calcStartBlocks

        Bake::IDEInterface.instance.set_build_info(@mainConfig.parent.name, @mainConfig.name, Blocks::ALL_BLOCKS.length)

        ideAbort = false
        Blocks::Block.reset_delayed_result

        begin
          Blocks::Block.init_threads()
          result = callBlocks(startBlocks, :startup, true)
          if Bake.options.clean or Bake.options.rebuild
            if not Bake.options.stopOnFirstError or result
              result = callBlocks(startBlocks, :clean) && result
            end
          end
          if Bake.options.rebuild or not Bake.options.clean
            if not Bake.options.stopOnFirstError or result
              result = callBlocks(startBlocks, :execute) && result
            end
          end
        rescue AbortException
          ideAbort = true
        end
        result = callBlocks(startBlocks, :exits, true) && result

        if ideAbort || Bake::IDEInterface.instance.get_abort
          Bake.formatter.printError("\n#{taskType} aborted.")
          ExitHelper.set_exit_code(1)
          return
        end

        if Bake.options.cc2j_filename
          require "json"
          File.write(Bake.options.cc2j_filename, JSON.pretty_generate(Blocks::CC2J))
        end

        if Bake.options.filelist && !Bake.options.dry
          mainBlock = Blocks::ALL_BLOCKS[Bake.options.main_project_name+","+Bake.options.build_config]
          Dir.chdir(mainBlock.projectDir) do
            FileUtils.mkdir_p(mainBlock.output_dir)
            File.open(mainBlock.output_dir + "/" + "global-file-list.txt", 'wb') do |f|
              Bake.options.filelist.sort.each do |entry|
                f.puts(entry)
              end
            end
          end
        end

        if result == false
          Bake.formatter.printError("\n#{taskType} failed.")
          ExitHelper.set_exit_code(1)
          return
        else
          if Bake.options.linkOnly and @@linkBlock == 0
            Bake.formatter.printSuccess("\nNothing to link.")
          else
            Bake.formatter.printSuccess("\n#{taskType} done.")
          end
        end
      rescue SystemExit
        Bake.formatter.printError("\n#{taskType} failed.") if ExitHelper.exit_code != 0
      end

    end

    def connect()
      if Bake.options.socket != 0
        Bake::IDEInterface.instance.connect(Bake.options.socket)
      end
    end

    def disconnect()
      if Bake.options.socket != 0
        Bake::IDEInterface.instance.disconnect()
      end
    end

  end
end

trap("SIGINT") do
  Bake::IDEInterface.instance.set_abort(1)
end