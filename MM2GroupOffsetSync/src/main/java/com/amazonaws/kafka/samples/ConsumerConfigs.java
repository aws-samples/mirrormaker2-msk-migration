package com.amazonaws.kafka.samples;

import org.apache.kafka.clients.CommonClientConfigs;
import org.apache.kafka.clients.consumer.ConsumerConfig;
import org.apache.kafka.common.config.SslConfigs;
import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;
import java.io.FileInputStream;
import java.io.IOException;
import java.util.Properties;

class ConsumerConfigs {

    private static final String BOOTSTRAP_SERVERS_CONFIG = "http://127.0.0.1:9092";
    private static final String SSL_TRUSTSTORE_LOCATION_CONFIG = "/tmp/kafka.client.truststore.jks";
    private static final String SSL_KEYSTORE_LOCATION_CONFIG = "/tmp/kafka.client.keystore.jks";
    private static final String SECURITY_PROTOCOL_CONFIG = "SSL";
    private static final String SSL_KEYSTORE_PASSWORD_CONFIG = "password";
    private static final String SSL_KEY_PASSWORD_CONFIG = "password";
    private static final String GROUP_ID_CONFIG = "mm2OffsetSync";
    private static final String CLIENT_ID_CONFIG = "mm2OffsetSync";
    private static final String EXCLUDE_INTERNAL_TOPICS = "true";

    private static boolean sslEnable = false;
    private static boolean mTLSEnable = false;

    private static final Logger logger = LogManager.getLogger(ConsumerConfigs.class);

    static Properties consumerConfig() {
        if (MM2GroupOffsetSync.mTLSEnable){
            mTLSEnable = true;
            sslEnable = true;
        } else {
            sslEnable = MM2GroupOffsetSync.sslEnable;
        }

        Properties consumerProps = new Properties();
        Properties loadProps = new Properties();
        consumerProps.setProperty(org.apache.kafka.clients.consumer.ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest");
        consumerProps.setProperty(ConsumerConfig.CLIENT_ID_CONFIG, CLIENT_ID_CONFIG);
        consumerProps.setProperty(ConsumerConfig.EXCLUDE_INTERNAL_TOPICS_CONFIG, EXCLUDE_INTERNAL_TOPICS);

        try (FileInputStream file = new FileInputStream(MM2GroupOffsetSync.propertiesFilePath)) {
            loadProps.load(file);
            consumerProps.setProperty(org.apache.kafka.clients.consumer.ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, loadProps.getProperty("BOOTSTRAP_SERVERS_CONFIG", BOOTSTRAP_SERVERS_CONFIG).equals("") ? BOOTSTRAP_SERVERS_CONFIG : loadProps.getProperty("BOOTSTRAP_SERVERS_CONFIG", BOOTSTRAP_SERVERS_CONFIG));
            consumerProps.setProperty(org.apache.kafka.clients.consumer.ConsumerConfig.GROUP_ID_CONFIG, loadProps.getProperty("GROUP_ID_CONFIG", GROUP_ID_CONFIG).equals("") ? GROUP_ID_CONFIG : loadProps.getProperty("GROUP_ID_CONFIG", GROUP_ID_CONFIG));

            //configure the following three settings for SSL Encryption
            if (sslEnable){
                consumerProps.setProperty(CommonClientConfigs.SECURITY_PROTOCOL_CONFIG, SECURITY_PROTOCOL_CONFIG);
                consumerProps.setProperty(SslConfigs.SSL_TRUSTSTORE_LOCATION_CONFIG, loadProps.getProperty("SSL_TRUSTSTORE_LOCATION_CONFIG", SSL_TRUSTSTORE_LOCATION_CONFIG).equals("") ? SSL_TRUSTSTORE_LOCATION_CONFIG : loadProps.getProperty("SSL_TRUSTSTORE_LOCATION_CONFIG", SSL_TRUSTSTORE_LOCATION_CONFIG));
            }
            if (mTLSEnable){
                consumerProps.setProperty(SslConfigs.SSL_KEYSTORE_LOCATION_CONFIG, loadProps.getProperty("SSL_KEYSTORE_LOCATION_CONFIG", SSL_KEYSTORE_LOCATION_CONFIG).equals("") ? SSL_KEYSTORE_LOCATION_CONFIG : loadProps.getProperty("SSL_KEYSTORE_LOCATION_CONFIG", SSL_KEYSTORE_LOCATION_CONFIG));
                consumerProps.setProperty(SslConfigs.SSL_KEYSTORE_PASSWORD_CONFIG, loadProps.getProperty("SSL_KEYSTORE_PASSWORD_CONFIG", SSL_KEYSTORE_PASSWORD_CONFIG).equals("") ? SSL_KEYSTORE_PASSWORD_CONFIG : loadProps.getProperty("SSL_KEYSTORE_PASSWORD_CONFIG", SSL_KEYSTORE_PASSWORD_CONFIG));
                consumerProps.setProperty(SslConfigs.SSL_KEY_PASSWORD_CONFIG, loadProps.getProperty("SSL_KEY_PASSWORD_CONFIG", SSL_KEY_PASSWORD_CONFIG).equals("") ? SSL_KEY_PASSWORD_CONFIG : loadProps.getProperty("SSL_KEY_PASSWORD_CONFIG", SSL_KEY_PASSWORD_CONFIG));
            }
            //consumerProps.put(SslConfigs.SSL_TRUSTSTORE_PASSWORD_CONFIG,  "");

        } catch (IOException e) {
            logger.info("Properties file not found in location: {}, using defaults \n", MM2GroupOffsetSync.propertiesFilePath);
            consumerProps.setProperty(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, BOOTSTRAP_SERVERS_CONFIG);
            consumerProps.setProperty(ConsumerConfig.GROUP_ID_CONFIG, GROUP_ID_CONFIG);

            if (sslEnable){
                consumerProps.setProperty(CommonClientConfigs.SECURITY_PROTOCOL_CONFIG, SECURITY_PROTOCOL_CONFIG);
                consumerProps.setProperty(SslConfigs.SSL_TRUSTSTORE_LOCATION_CONFIG, SSL_TRUSTSTORE_LOCATION_CONFIG);
            }
            if (mTLSEnable){
                consumerProps.setProperty(SslConfigs.SSL_KEYSTORE_LOCATION_CONFIG, SSL_KEYSTORE_LOCATION_CONFIG);
                consumerProps.setProperty(SslConfigs.SSL_KEYSTORE_PASSWORD_CONFIG, SSL_KEYSTORE_PASSWORD_CONFIG);
                consumerProps.setProperty(SslConfigs.SSL_KEY_PASSWORD_CONFIG, SSL_KEY_PASSWORD_CONFIG);
            }

        }

        return consumerProps;
    }


}
