package org.egov.jenkins

import org.egov.jenkins.models.BuildConfig
import org.egov.jenkins.models.JobConfig
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
            if (configs.get(i).get("name").equalsIgnoreCase(jobName)) {
                filteredJobConfigs.add(configs.get(i));
            }
        }

        if(filteredJobConfigs.isEmpty())
            throw new Exception("No config exists for this job! ")

        List<JobConfig> jobConfigs = populateConfigs(filteredJobConfigs, env);

        return jobConfigs;

    }

    static List<JobConfig> populateConfigs(def jobConfigs, def env) {
        List<JobConfig> config = new ArrayList<>();
        for (int jobConfigIndex = 0; jobConfigIndex < jobConfigs.size(); jobConfigIndex++) {
            Map<String, Object> job = jobConfigs.get(jobConfigIndex)
            List<BuildConfig> buildConfigs = new ArrayList<>();

            if( ! job.get("build") instanceof Map)
                throw new Exception("Invalid job config, build config missing ! - Job "+job.get("name"))

            for (int buildConfigIndex = 0; buildConfigIndex < job.get("build").size();
                 buildConfigIndex++) {
                BuildConfig buildConfig = validateAndEnrichBuildConfig(job.get("build").get(buildConfigIndex), env)
                buildConfigs.add(buildConfig);
            }  
            JobConfig jobConfig = new JobConfig(job.name, buildConfigs);
            config.add(jobConfig);
        }

        return config;
    }

    static BuildConfig validateAndEnrichBuildConfig(Map<String,Object> buildYaml, def env){
        String workDir, dockerFile, buildContext = "";

        if(buildYaml.get('work-dir') == null)
            throw new Exception("Working Directory is empty for config");

        if(buildYaml.get('image-name') == null)
            throw new Exception("Image Name is empty for config");


        workDir = buildYaml.get('work-dir')

        if (buildYaml.get('dockerfile') == null)
            dockerFile = workDir + "/Dockerfile";
        else
            dockerFile = buildYaml.get('dockerfile');

        Path workDirPath = Paths.get(workDir);
        Path dockerFilePath = Paths.get(dockerFile);

        workDir = workDirPath.normalize()
        dockerFile = dockerFilePath.normalize()

        buildContext = "./" + getCommonBasePath(workDir, dockerFile);

        return new BuildConfig(buildContext, buildYaml.get('image-name'), dockerFile, workDir);

    }

    public static String getCommonBasePath(String path, String path1){
        String[] pathArray = path.split("/");
        String[] path1Array = path1.split("/");

        List<String> commonPaths = new ArrayList<>();

        for(int i=0; i<Integer.min(pathArray.length, path1Array.length); i++){
            if(pathArray[i].equals(path1Array[i]))
                commonPaths.add(pathArray[i]);
            else
                break;
        }

        return String.join("/", commonPaths);

    }

}
