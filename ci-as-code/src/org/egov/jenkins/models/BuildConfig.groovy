package org.egov.jenkins.models

class BuildConfig {

    private String context;
    private String imageName;

    BuildConfig(String context, String imageName) {
        this.context = context
        this.imageName = imageName
    }

    String getContext() {
        return context
    }


    String getImageName() {
        return imageName
    }


    @Override
    public String toString() {
        return "BuildConfig{" +
                "context='" + context + '\'' +
                ", imageName='" + imageName + '\'' +
                '}';
    }
}

