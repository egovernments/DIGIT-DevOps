package org.egov.jenkins.models

class BuildConfig {

    private String context;
    private String imageName;
    private String dockerFile;

    BuildConfig(String context, String imageName, String dockerFile) {
        this.context = context
        this.imageName = imageName
        this.dockerFile = dockerFile
    }

    String getContext() {
        return context
    }


    String getImageName() {
        return imageName
    }

    String getDockerFile() {
        return dockerFile
    }


    @Override
    public String toString() {
        return "BuildConfig{" +
                "context='" + context + '\'' +
                ", imageName='" + imageName + '\'' +
                ", dockerFile='" + dockerFile + '\'' +
                '}';
    }
}

