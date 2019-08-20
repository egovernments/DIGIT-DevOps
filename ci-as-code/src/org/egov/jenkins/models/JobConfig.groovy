package org.egov.jenkins.models

class JobConfig {

    private String name;
    private List<BuildConfig> buildConfigs;

    JobConfig(String name, List<BuildConfig> buildConfigs) {
        this.name = name
        this.buildConfigs = buildConfigs
    }

    public String getName() {
        return name;
    }

    public List<BuildConfig> getBuildConfigs() {
        return buildConfigs;
    }


    @Override
    public String toString() {
        return "JobConfig{" +
                "name='" + name + '\'' +
                ", buildConfigs=" + buildConfigs +
                '}';
    }
}

