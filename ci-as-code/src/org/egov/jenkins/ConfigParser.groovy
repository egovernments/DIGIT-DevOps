package org.egov.jenkins

import org.egov.jenkins.models.BuildConfig
import org.egov.jenkins.models.JobConfig;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

class ConfigParser {

    static List<JobConfig> parseConfig(def yaml, def env) {
        String jobName = env.JOB_NAME;
        if( ! yaml.config instanceof List)
            throw new Exception("Invalid job config file format!")

        List<Object> configs = yaml.config;
        List<Object> filteredJobConfigs = new ArrayList<>();

        for (int i = 0; i < configs.size(); i++) {
            if (configs.get(i).getName().equalsIgnoreCase(jobName)) {
                filteredJobConfigs.add(configs.get(i));
            }
        }

        if(filteredJobConfigs.isEmpty())
            throw new Exception("No config exists for this job! ")

        List<JobConfig> jobConfigs = populateConfigs(filteredJobConfigs);

        return jobConfigs;

    }

    static List<JobConfig> populateConfigs(List<Object> jobConfigs) {
        List<JobConfig> config = new ArrayList<>();

        for (int jobConfigIndex = 0; jobConfigIndex < jobConfigs.size(); jobConfigIndex++) {
            Map<String, Object> job = jobConfigs.get(jobConfigIndex)
            List<BuildConfig> buildConfigs = new ArrayList<>();

            if( ! job.get("build") instanceof Map)
                throw new Exception("Invalid job config, build config missing ! - Job "+job.get("name"))

            for (int buildConfigIndex = 0; buildConfigIndex < job.get("build").size();
                 buildConfigIndex++) {
                BuildConfig buildConfig = validateAndEnrichBuildConfig(job.get("build").get(buildConfigIndex))
                buildConfigs.add(buildConfig);
            }
            JobConfig jobConfig = new JobConfig(job.name, buildConfigs);
            config.add(jobConfig);
        }

        return config;
    }

    static BuildConfig validateAndEnrichBuildConfig(Map<String,Object> buildYaml){
        String workDir, dockerFile, buildContext = "";
        String workspace = System.getenv('JENKINS_AGENT_WORKDIR')+ "/" + "workspace"

        if(buildYaml.get('workDir') == null)
            throw new Exception("Working Directory is empty for config");

        if(buildYaml.get('imageName') == null)
            throw new Exception("Image Name is empty for config");


        workDir = workspace + "/" + buildYaml.workDir

        if (buildYaml.dockerFile == null)
            dockerFile = workDir + "/Dockerfile";
        else
            dockerFile = workspace + "/" + buildYaml.dockerFile;

        Path workDirPath = Paths.get(workDir);
        Path dockerFilePath = Paths.get(dockerFile);

        if( ! Files.exists(workDirPath) || ! Files.isDirectory(workDirPath))
            throw new Exception("Working directory does not exist!");

        if( ! Files.exists(dockerFilePath) || ! Files.isRegularFile(dockerFilePath))
            throw new Exception("Docker file does not exist!");

        workDir = workDirPath.toAbsolutePath()
        dockerFile = dockerFilePath.toAbsolutePath()

        buildContext = getCommonBasePath(workDir, dockerFile);

        return new BuildConfig(buildContext, buildYaml.imageName, dockerFile, workDir);

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
