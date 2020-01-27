package org.egov.jenkins

import org.egov.jenkins.models.JobConfig

class Utils {

    static List<String> foldersToBeCreatedOrUpdated(List<JobConfig> configs, def env) {

        Set<String> folders = new HashSet<>();

        configs.each { config ->
            String configName = config.getName();	   
            while(configName.lastIndexOf("/")!=-1) {
            	configName= configName.substring(0, configName.lastIndexOf("/"));
                folders.add(configName);   
            }
        }

        List<String> uniqueFolders = folders.toList();
        for (int j = 0; j < uniqueFolders.size()-1; j++) { 
        	  
            if (numberOfOccurrences(uniqueFolders.get(j),"/") > numberOfOccurrences(uniqueFolders.get(j + 1),"/")) { 
  
                String temp = uniqueFolders.get(j); 
                uniqueFolders.set(j,uniqueFolders.get(j + 1)); 
                uniqueFolders.set(j+1,temp);
  
                j = -1; 
            } 
        } 
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
