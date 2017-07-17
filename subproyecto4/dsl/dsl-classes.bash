class OSRFBase
{
   static void create(Job job)
   {
     job.with {
         description 'Automatic generated job by DSL jenkins. Please do not edit manually'

        publishers { 
          extendedEmail('$DEFAULT_RECIPIENTS, admin-jenkins@osrfoundation.org',
                        '$DEFAULT_SUBJECT',
                        '$DEFAULT_CONTENT')       
        }
     }
   }
}

class OSRFLinuxBase extends OSRFBase
{
 static void create(Job job)
 {
   OSRFBase.create(job)
   job.with 
   {
     label "docker"
        
     parameters { stringParam('RTOOLS_BRANCH','default','release-tool branch to use') }

     steps 
     {
       systemGroovyCommand("build.setDescription('RTOOLS_BRANCH: ' +
                            build.buildVariableResolver.resolve('RTOOLS_BRANCH'));")
           
       shell("""
          [[ -d ./scripts ]] &&  rm -fr ./scripts
          hg clone http://bitbucket.org/osrf/release-tools scripts -b \${RTOOLS_BRANCH} 
          """)
     }

     wrappers {
       colorizeOutput()
     }
   }
  }
}

class OSRFLinuxCompilation extends OSRFLinuxBase
{
  static void create(Job job)
  {
    OSRFLinuxBase.create(job)

    def mail_content ='''
     $DEFAULT_CONTENT
     Test summary:
     -------------
     * Total of ${TEST_COUNTS, var="total"} tests : ${TEST_COUNTS, var="fail"} failed and   
       ${TEST_COUNTS, var="skip"

     Data log:
     ${FAILED_TESTS}
  '''
  
  job.with
    {
      priority 100

      logRotator {
        numToKeep(15)
      }

      publishers
      {
         // compilers warnings
         warnings(['GNU C Compiler 4 (gcc)'])

         // special content with testing failures
         extendedEmail('$DEFAULT_RECIPIENTS, admin-jenkins@osrfoundation.org',
                        '$DEFAULT_SUBJECT',
                         content)
         // junit plugin is not implemented. Use configure for it
         configure { project ->
            project / publishers << 'hudson.tasks.junit.JUnitResultArchiver' {
                 testResults('build/test_results/*.xml')
                 keepLongStdio false
                 testDataPublishers()
            }
         }
         // cppcheck is not implemented. Use configure for it
         configure { project ->
           project / publishers / 'org.jenkinsci.plugins.cppcheck.CppcheckPublisher' /
            cppcheckConfig {
              pattern('build/cppcheck_results/*.xml')
              ignoreBlankFiles true
              allowNoReport false
            }
         }
      }
    }
  }
} 

