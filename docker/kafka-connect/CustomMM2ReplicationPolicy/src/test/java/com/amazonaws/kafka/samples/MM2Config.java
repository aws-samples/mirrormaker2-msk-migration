package com.amazonaws.kafka.samples;


import java.util.HashMap;
import java.util.Map;

class MM2Config {

    private boolean sslEnable = false;
    private boolean mTLSEnable = false;

    Map<String, Object> mm2config() {

        Map<String, Object> mm2Props = new HashMap<>();
        mm2Props.put("source.cluster.alias", "msksource");
        mm2Props.put("clusters", "msksource,mskdest");


        /*mm2Props.put("bootstrap.servers", ConsumerConfigs.consumerConfig().getProperty(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG));

        if (MM2GroupOffsetSync.mTLSEnable){
            mTLSEnable = true;
            sslEnable = true;
        } else {
            sslEnable = MM2GroupOffsetSync.sslEnable;
        }

        if (sslEnable){
            mm2Props.put(CommonClientConfigs.SECURITY_PROTOCOL_CONFIG, "SSL");
            mm2Props.put(SslConfigs.SSL_TRUSTSTORE_LOCATION_CONFIG, ConsumerConfigs.consumerConfig().getProperty(SslConfigs.SSL_TRUSTSTORE_LOCATION_CONFIG));
        }
        if (mTLSEnable){
            mm2Props.put(SslConfigs.SSL_KEYSTORE_LOCATION_CONFIG, ConsumerConfigs.consumerConfig().getProperty(SslConfigs.SSL_KEYSTORE_LOCATION_CONFIG));
            mm2Props.put(SslConfigs.SSL_KEYSTORE_PASSWORD_CONFIG, ConsumerConfigs.consumerConfig().getProperty(SslConfigs.SSL_KEYSTORE_PASSWORD_CONFIG));
            mm2Props.put(SslConfigs.SSL_KEY_PASSWORD_CONFIG, ConsumerConfigs.consumerConfig().getProperty(SslConfigs.SSL_KEY_PASSWORD_CONFIG));
        }


        if (!MM2GroupOffsetSync.replicationPolicyClass.equalsIgnoreCase(String.valueOf(MirrorClientConfig.REPLICATION_POLICY_CLASS_DEFAULT))){
            mm2Props.put(MirrorClientConfig.REPLICATION_POLICY_CLASS, MM2GroupOffsetSync.replicationPolicyClass);
        }

        if (!MM2GroupOffsetSync.replicationPolicySeparator.equalsIgnoreCase(MirrorClientConfig.REPLICATION_POLICY_SEPARATOR_DEFAULT)){
            mm2Props.put(MirrorClientConfig.REPLICATION_POLICY_SEPARATOR, MM2GroupOffsetSync.replicationPolicySeparator);
        }*/

        return mm2Props;
    }
}
