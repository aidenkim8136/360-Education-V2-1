import React from 'react';
import { View, Text, StyleSheet } from 'react-native';

export default function HomeScreen() {
  return (
    <View style={styles.container}>
      <Text style={styles.title}>360 Education V2 (Expo)</Text>
      <Text style={styles.subtitle}>Firebase and basic navigation are set up.</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 16
  },
  title: {
    fontSize: 22,
    fontWeight: '700',
    marginBottom: 8
  },
  subtitle: {
    fontSize: 14,
    color: '#444'
  }
});
