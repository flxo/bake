module Bake

  class Subst
  
    # this is done lazy because usually there is no need to calculate that
    def self.lazyPathes
      return unless @@lazy
      
      cppCmd = @@toolchain[:COMPILER][:CPP][:COMMAND]
      cCmd = @@toolchain[:COMPILER][:C][:COMMAND]
      asmCmd = @@toolchain[:COMPILER][:ASM][:COMMAND]
      archiverCmd = @@toolchain[:ARCHIVER][:COMMAND]
      linkerCmd = @@toolchain[:LINKER][:COMMAND]
        
      if @@config.toolchain
        linkerCmd = @@config.toolchain.linker.command if @@config.toolchain.linker and @@config.toolchain.linker.command != ""
        archiverCmd = @@config.toolchain.archiver.command if @@config.toolchain.linker and @@config.toolchain.archiver.command != ""
        @@config.toolchain.compiler.each do |c|
          if c.ctype == :CPP
            cppCmd = c.command
          elsif c.ctype == :C
            cCmd = c.command
          elsif c.ctype == :ASM
            asmCmd = c.command
          end
        end
      end 
      
      @@cppExe      = File.which(cppCmd) 
      @@cExe        = File.which(cCmd)
      @@asmExe      = File.which(asmCmd)
      @@archiverExe = File.which(archiverCmd)
      @@linkerExe   = File.which(linkerCmd)
      
      @@lazy = false
    end
    
    def self.itute(config, projName, isMainProj, toolchain)
      @@lazy = true
      @@config = config
      @@toolchain = toolchain
      
      @@configName = config.name
      @@projDir = config.parent.get_project_dir
      @@projName = projName
      @@resolvedVars = 0
      @@configFilename = config.file_name
      
      @@artifactName = ""
      if Metamodel::ExecutableConfig === config
        if not config.artifactName.nil?
          @@artifactName = config.artifactName.name
        elsif config.defaultToolchain != nil
          basedOnToolchain = Bake::Toolchain::Provider[config.defaultToolchain.basedOn]
          if basedOnToolchain != nil
            @@artifactName = projName+basedOnToolchain[:LINKER][:OUTPUT_ENDING]
          end
        end
      end
      
      if isMainProj
        @@userVarMap = {}
      else
        @@userVarMap = @@userVarMapMain.clone
      end
      
      config.set.each do |s|
     
        if (s.value != "" and s.cmd != "")
          Bake.formatter.printError("value and cmd attributes must be used exclusively", s)
          ExitHelper.exit(1)
        end
        
        if (s.value != "")
          setName = substString(s.name, s)
          if (setName.empty?)
            Bake.formatter.printWarning("Name of variable must not be empty - variable will be ignored", s)
          else
            @@userVarMap[s.name] = substString(s.value, s)
          end
        else
          cmd_result = false
          consoleOutput = ""
          begin
            Dir.chdir(@@projDir) do
              cmd = [substString(s.cmd, s)]
              cmd_result, consoleOutput = ProcessHelper.run(cmd)
              @@userVarMap[s.name] = consoleOutput.chomp
            end
          rescue Exception=>e
            consoleOutput = e.message
          end
          if (cmd_result == false)
            Bake.formatter.printWarning("Command not successful, variable #{s.name} will be set to \"\" (#{consoleOutput.chomp}).", s)
            @@userVarMap[s.name] = ""
          end          
        end
        
      end
      
      @@userVarMapMain = @@userVarMap.clone if isMainProj
     
      3.times {
        subst(config);
        substToolchain(toolchain)
      }
      
      @@resolvedVars = 0
      lastFoundInVar = -1 
      100.times do
        subst(config)
        break if @@resolvedVars == 0 or (@@resolvedVars >= lastFoundInVar and lastFoundInVar >= 0)
        lastFoundInVar = @@resolvedVars 
      end      
      if (@@resolvedVars > 0)
        Bake.formatter.printError("Cyclic variable substitution detected", config.file_name)
        ExitHelper.exit(1)
      end
      
    end
    
    def self.substString(str, elem=nil)
      substStr = ""
      posSubst = 0
      while (true)
        posStart = str.index("$(", posSubst)
        break if posStart.nil?
        posEnd = str.index(")", posStart)
        break if posEnd.nil?
        substStr << str[posSubst..posStart-1] if posStart>0
      
        @@resolvedVars += 1
        var = str[posStart+2..posEnd-1]

        if Bake.options.vars.has_key?(var)
          substStr << Bake.options.vars[var]  
        elsif @@userVarMap.has_key?(var)
          substStr << @@userVarMap[var]       
        elsif var == "MainConfigName"
          substStr << Bake.options.build_config
        elsif var == "MainProjectName"
          substStr << Bake.options.main_project_name
        elsif var == "MainProjectDir"
          substStr << Bake.options.main_dir
        elsif var == "ConfigName"
         substStr << @@configName
        elsif var == "ProjectName"
          substStr << @@projName
        elsif var == "ProjectDir"
          substStr << @@projDir
        elsif var == "OutputDir"
          if @@projName == Bake.options.main_project_name
            substStr << Bake.options.build_config
          else
            substStr << @@configName + "_" + Bake.options.main_project_name + "_" + Bake.options.build_config
          end
        elsif var == "Time"
          substStr << Time.now.to_s
        elsif var == "Hostname"
          substStr << Socket.gethostname
        elsif var == "ArtifactName"
          substStr << @@artifactName
        elsif var == "ArtifactNameBase"
          substStr << @@artifactName.chomp(File.extname(@@artifactName))
        elsif var == "CPPPath"
          self.lazyPathes
          substStr << @@cppExe
        elsif var == "CPath"
          self.lazyPathes
          substStr << @@cExe
        elsif var == "ASMPath"
          self.lazyPathes
          substStr << @@asmExe
        elsif var == "ArchiverPath"
          self.lazyPathes
          substStr << @@archiverExe
        elsif var == "LinkerPath"
          self.lazyPathes
          substStr << @@linkerExe
        elsif var == "Roots"
          substStr << "___ROOTS___"
        elsif var == "/"
          if Bake::Utils::OS.windows?
            substStr << "\\"
          else
            substStr << "/"
          end
        elsif ENV[var]
          substStr << ENV[var]
        else
          if Bake.options.verboseHigh
            msg = "Substitute variable '$(#{var})' with empty string"
            if elem
              Bake.formatter.printInfo(msg, elem)
            else
              Bake.formatter.printInfo(msg +  " in the toolchain", @@config)
            end
          end
          substStr << ""
        end
      
        posSubst = posEnd + 1
      end
      substStr << str[posSubst..-1]
      substStr
    end

    def self.substToolchain(elem)
      if Hash === elem
        elem.each do |k, e|
          if Hash === e or Array === e
            substToolchain(e)
          elsif String === e
            elem[k] = substString(e)
          end
        end
      elsif Array === elem
        elem.each_with_index do |e, i|
          if Hash === e or Array === e
            substToolchain(e)
          elsif String === e
            elem[i] = substString(e)
          end
        end
      end
    end
    
    def self.subst(elem)
      elem.class.ecore.eAllAttributes_derived.each do |a|
        next if a.name == "file_name" or a.name == "line_number"
        return if Metamodel::Set === elem.class
        return if Metamodel::DefaultToolchain === elem
        return if Metamodel::Toolchain === elem.class
        next if a.eType.name != "EString" 
        substStr = substString(elem.getGeneric(a.name), elem)
        elem.setGeneric(a.name, substStr)
      end
    
      childsRefs = elem.class.ecore.eAllReferences.select{|r| r.containment}
      childsRefs.each do |c|
        elem.getGenericAsArray(c.name).each { |child| subst(child) }
      end     
    end
  
  end
  
end

