// Create the default ci jobs
def ci_default_job = job("gazebo-default-devel-precise-amd64”)

// Use the linux compilation as base
OSRFLinuxCompilation.create(ci_default_job)

ci_default_job.with
{
  scm {
   hg('http://bitbucket.org/osrf/gazebo')
  }

  triggers {
    scm('*/5 * * * *') 
  }

   steps { 
    shell("""
          export DISTRO=precise
          export ARCH=amd64  
          /bin/bash -x ./scripts/jenkins-scripts/gazebo-default-gui-test.bash")
   }
