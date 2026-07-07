import React from 'react';
import { View, Text, Button, StyleSheet } from 'react-native';

export default function LandingScreen({ navigation }) {
  return (
    <View style={styles.container}>
      <Text style={styles.title}>Welcome to 360 Education</Text>
      <Text style={styles.subtitle}>Cross-platform build (Expo)</Text>
      <View style={{ height: 20 }} />
      <Button title="Get Started" onPress={() => navigation.navigate('Auth')} />
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, alignItems: 'center', justifyContent: 'center', padding: 16 },
  title: { fontSize: 22, fontWeight: '700' },
  subtitle: { fontSize: 14, color: '#444' }
});
