package org.egov.jenkins

import org.egov.jenkins.models.JobConfig

class Utils {

    static List<String> foldersToBeCreatedOrUpdated(List<JobConfig> configs, def env) {

        Set<String> folders = new HashSet<>();

        configs.each { config ->
            int index = config.getName().lastIndexOf("/");
            if(index != -1)
                folders.add(config.getName().substring(0, index));
        }

        Comparator<String> comparator = new Comparator<String>() {
            @Override
            int compare(String o1, String o2) {
                return Integer.compare(numberOfOccurrences(o1, "/"), numberOfOccurrences(o2, "/"));
            }
        };



        List<String> uniqueFolders = folders.toList();
        uniqueFolders.sort(comparator);
        return uniqueFolders;
    }

    private static int numberOfOccurrences(String source, String match){
        return source.length() - source.replace(match, "").length();
    }

    static String getDirName(String url) {

        String dirName = "";

        int startIndex = url.lastIndexOf("/");
	    int endIndex = url.lastIndexOf(".");
        dirName = url.substring(startIndex+1,endIndex);
        return dirName;

    }

}