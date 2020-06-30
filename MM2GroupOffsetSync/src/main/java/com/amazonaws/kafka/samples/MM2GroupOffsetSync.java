package com.amazonaws.kafka.samples;

import com.beust.jcommander.JCommander;
import com.beust.jcommander.Parameter;
import org.apache.kafka.clients.admin.AdminClient;
import org.apache.kafka.connect.mirror.MirrorClientConfig;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

import java.util.Properties;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

public class MM2GroupOffsetSync {

    @Parameter(names = {"--help", "-h"}, help = true)
    private boolean help = false;

    @Parameter(names = {"--topic", "-t"})
    static String topic = "ExampleTopic";

    @Parameter(names = {"--propertiesFilePath", "-pfp"})
    static String propertiesFilePath = "/tmp/kafka/consumer.properties";

    @Parameter(names = {"--runFor", "-rf"})
    private static Integer runFor = 0;

    @Parameter(names = {"--interval", "-int"})
    private static Long interval = 20L;

    @Parameter(names = {"--sslEnable", "-ssl"})
    static boolean sslEnable = false;

    @Parameter(names = {"--mTLSEnable", "-mtls"})
    static boolean mTLSEnable = false;

    @Parameter(names = {"--sourceCluster", "-src"})
    static String sourceCluster = "msksource";

    @Parameter(names = {"--consumerGroupID", "-cgi"})
    private static String consumerGroupID = "mm2TestConsumer1";

    @Parameter(names = {"--replicationPolicySeparator", "-rps"})
    static String replicationPolicySeparator = MirrorClientConfig.REPLICATION_POLICY_SEPARATOR_DEFAULT;

    @Parameter(names = {"--replicationPolicyClass", "-rpc"})
    static String replicationPolicyClass = String.valueOf(MirrorClientConfig.REPLICATION_POLICY_CLASS_DEFAULT);

    private static final Logger logger = LogManager.getLogger(MM2GroupOffsetSync.class);

    private void shutdown(ScheduledExecutorService executor, AdminClient adminClient, Long startTime) {
        logger.info("Shutdown called. Starting to exit. \n");

        try {
            executor.shutdown();

            if (!executor.awaitTermination(1L, TimeUnit.SECONDS)) {
                executor.shutdownNow();
            }
        } catch (InterruptedException e) {
            logger.error(Util.stackTrace(e));
        } finally {
            adminClient.close();
        }
        long endTime = System.nanoTime();
        logger.info("End Timestamp: {} \n", TimeUnit.NANOSECONDS.toMillis(endTime));
        long executionTime = endTime - startTime;
        logger.info("Execution time in milliseconds: {} \n", TimeUnit.NANOSECONDS.toMillis(executionTime));
    }

    private void runConsumerOffsetSyncs() {
        final ScheduledExecutorService executor = Executors.newSingleThreadScheduledExecutor();
        final AdminClient adminClient = getAdminClient(getAdminClientConfig());
        long startTime = System.nanoTime();
        logger.info("Start Time: {} \n", TimeUnit.NANOSECONDS.toMillis(startTime));
        ConsumerOffsetsSync consumerOffsetsSync = new ConsumerOffsetsSync(consumerGroupID, adminClient);
        executor.scheduleAtFixedRate(consumerOffsetsSync, 0L, MM2GroupOffsetSync.interval, TimeUnit.SECONDS);

        Runtime.getRuntime().addShutdownHook(new Thread(() -> shutdown(executor, adminClient, startTime)));

        if (runFor > 0) {

            try {
                TimeUnit.SECONDS.sleep(runFor);
            } catch (InterruptedException e) {
                logger.error(Util.stackTrace(e));
            }
            logger.info("Reached specified run time of {} seconds. Shutting down. \n", runFor);
            System.exit(0);

        }
    }

    private Properties getAdminClientConfig() {
        return ConsumerConfigs.consumerConfig();
    }

    private AdminClient getAdminClient(Properties config) {
        return AdminClient.create(config);
    }

    public static void main(String[] args) {

        final MM2GroupOffsetSync mm2Utils = new MM2GroupOffsetSync();
        JCommander jc = JCommander.newBuilder()
                .addObject(mm2Utils)
                .build();
        jc.parse(args);
        if (mm2Utils.help) {
            jc.usage();
            return;
        }

        mm2Utils.runConsumerOffsetSyncs();
    }
}
