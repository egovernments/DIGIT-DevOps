package org.egov.jenkins

import org.egov.jenkins.models.BuildConfig
import org.egov.jenkins.models.JobConfig;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

class ConfigParser {

    static List<JobConfig> parseConfig(def yaml, def env) {
        List<JobConfig> configs = populateConfigs(yaml.config);
        String jobName = env.JOB_NAME;

        List<JobConfig> filteredJobConfigs = new ArrayList<>();

        configs.each { config ->
            if (config.getName().equalsIgnoreCase(jobName)) {
                filteredJobConfigs.add(config);
            }
        }
        if (filteredJobConfigs.isEmpty())
            throw new Exception("Invalid Job");

        return filteredJobConfigs;

    }

    static List<JobConfig> populateConfigs(def yaml) {
        println System.getEnv("WORKSPACE");
        List<JobConfig> config = new ArrayList<>();
        yaml.each { job ->
            validateJobConfig(job)
            List<BuildConfig> buildConfigs = new ArrayList<>();
            job.build.each { build ->
                validateAndEnrichBuildConfig(build)
                String buildContext = getCommonPath(build.workDir, build.dockerFile);
                println buildContext

                BuildConfig buildConfig = new BuildConfig(buildContext, build.imageName, build.dockerFile, build.workDir);
                buildConfigs.add(buildConfig);
            }
            JobConfig jobConfig = new JobConfig(job.name, buildConfigs);
            config.add(jobConfig);
        }

        return config;
    }

    static void validateAndEnrichBuildConfig(Map<String,Object> buildConfig){
        String dockerFile = "";
        if(buildConfig.get('workDir') == null)
            throw new Exception("Working Directory is empty for config");
        
        if(buildConfig.get('imageName') == null)
            throw new Exception("Image Name is empty for config");    

        if (buildConfig.dockerFile == null)
            buildConfig.dockerFile = buildConfig.workDir + "/Dockerfile";           

        Path workDirPath = Paths.get(buildConfig.get('workDir'));
        Path dockerFilePath = Paths.get(buildConfig.get('dockerFile'));

        if( ! Files.exists(workDirPath) || ! Files.isDirectory(workDirPath))
            throw new Exception("Working directory does not exist!");

        if( ! Files.exists(dockerFilePath) || ! Files.isRegularFile(dockerFilePath))
            throw new Exception("Docker file does not exist!");

        buildConfig['workDir'] = workDirPath.toAbsolutePath()
        buildConfig['dockerFile'] = dockerFilePath.toAbsolutePath()

        println workDirPath.toAbsolutePath()
        println dockerFilePath.toAbsolutePath()

    }

    static void validateJobConfig(Map<String,Object> jobConfig){
        if(jobConfig.get('name') == null)
            throw new Exception("Job name is empty for config");       
    }
    
    private static String getCommonBasePath(String...  paths){
        String commonPath = "";
        String[][] folders = new String[paths.length][];

        for(int i=0; i<paths.length; i++){
            folders[i] = paths[i].split("/");
        }

        for(int j = 0; j< folders[0].length; j++){
            String s = folders[0][j];
            for(int i=1; i<paths.length; i++){
                if(!s.equals(folders[i][j]))
                    return commonPath;
            }
            commonPath += s + "/";
        }
        return commonPath;
    }        

}
