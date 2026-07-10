import React, { useState } from 'react';
import {
  View,
  Text,
  TextInput,
  StyleSheet,
  Alert,
  ScrollView,
  TouchableOpacity,
  ActivityIndicator,
} from 'react-native';
import { getFirebaseAuth, getFirestoreDb } from '../firebaseConfig';
import { createUserWithEmailAndPassword, signInWithEmailAndPassword, sendPasswordResetEmail } from 'firebase/auth';
import { doc, setDoc } from 'firebase/firestore';

const studentGrades = ['1', '2', '3', '4', '5', '6', '7', '8'];
const teacherOptions = ['9', '10', '11', '12', 'Current Teacher', 'Retired Teacher', 'Other'];

export default function AuthScreen() {
  const [isSignUp, setIsSignUp] = useState(true);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [name, setName] = useState('');
  const [gender, setGender] = useState('');
  const [role, setRole] = useState('student');
  const [studentGrade, setStudentGrade] = useState('1');
  const [parentEmail, setParentEmail] = useState('');
  const [parentPhone, setParentPhone] = useState('');
  const [teacherGradeOrOccupation, setTeacherGradeOrOccupation] = useState('9');
  const [teacherOtherExplanation, setTeacherOtherExplanation] = useState('');
  const [isBusy, setIsBusy] = useState(false);
  const auth = getFirebaseAuth();
  const db = getFirestoreDb();

  async function handlePrimary() {
    if (!email || !password) return Alert.alert('Enter email and password');

    if (isSignUp && !signupFieldsValid()) {
      return Alert.alert('Complete all required information');
    }

    try {
      setIsBusy(true);
      if (isSignUp) {
        const normalizedEmail = email.trim().toLowerCase();
        const res = await createUserWithEmailAndPassword(auth, normalizedEmail, password);
        await setDoc(doc(db, 'users_v2', res.user.uid), {
          id: res.user.uid,
          name: name.trim() || 'User',
          email: normalizedEmail,
          role,
          gender: gender.trim(),
          parentEmail: role === 'student' && parentEmail.trim() ? parentEmail.trim().toLowerCase() : null,
          parentPhone: role === 'student' && parentPhone.trim() ? parentPhone.trim() : null,
          studentGrade: role === 'student' ? studentGrade : null,
          teacherGradeOrOccupation: role === 'teacher' ? teacherGradeOrOccupation : null,
          teacherOtherExplanation: role === 'teacher' && teacherGradeOrOccupation === 'Other' ? teacherOtherExplanation.trim() : null,
          createdAt: Date.now(),
        });
      } else {
        await signInWithEmailAndPassword(auth, email.trim().toLowerCase(), password);
      }
    } catch (e) {
      Alert.alert('Auth error', e.message || 'Something went wrong');
    } finally {
      setIsBusy(false);
    }
  }

  function signupFieldsValid() {
    if (!name.trim() || !gender.trim()) return false;
    if (role === 'student') {
      return !!parentEmail.trim() && !!parentPhone.trim();
    }
    return teacherGradeOrOccupation !== 'Other' || !!teacherOtherExplanation.trim();
  }

  async function handleReset() {
    if (!email.trim()) return Alert.alert('Enter your email first');
    try {
      await sendPasswordResetEmail(auth, email.trim().toLowerCase());
      Alert.alert('Password reset email sent');
    } catch (e) {
      Alert.alert('Reset failed', e.message || 'Unable to send reset email');
    }
  }

  return (
    <ScrollView contentContainerStyle={styles.container} keyboardShouldPersistTaps="handled">
      <Text style={styles.title}>{isSignUp ? 'Create your account' : 'Welcome back'}</Text>
      <Text style={styles.subtitle}>360 Education with My Peers</Text>

      <TextInput
        placeholder="Email"
        value={email}
        onChangeText={setEmail}
        style={styles.input}
        autoCapitalize="none"
        keyboardType="email-address"
      />
      <TextInput
        placeholder="Password"
        value={password}
        onChangeText={setPassword}
        style={styles.input}
        secureTextEntry
      />

      {isSignUp && (
        <>
          <Text style={styles.sectionTitle}>I am a…</Text>
          <View style={styles.optionRow}>
            <OptionButton label="Student" selected={role === 'student'} onPress={() => setRole('student')} />
            <OptionButton label="Teacher" selected={role === 'teacher'} onPress={() => setRole('teacher')} />
          </View>

          <TextInput placeholder="Full name" value={name} onChangeText={setName} style={styles.input} />
          <TextInput placeholder="Gender" value={gender} onChangeText={setGender} style={styles.input} />

          {role === 'student' ? (
            <>
              <Text style={styles.sectionTitle}>Grade level</Text>
              <View style={styles.optionRowWrap}>
                {studentGrades.map((grade) => (
                  <OptionButton key={grade} label={`Grade ${grade}`} selected={studentGrade === grade} onPress={() => setStudentGrade(grade)} />
                ))}
              </View>
              <TextInput placeholder="Parent / guardian email" value={parentEmail} onChangeText={setParentEmail} style={styles.input} autoCapitalize="none" keyboardType="email-address" />
              <TextInput placeholder="Parent / guardian phone" value={parentPhone} onChangeText={setParentPhone} style={styles.input} keyboardType="phone-pad" />
            </>
          ) : (
            <>
              <Text style={styles.sectionTitle}>Grade level / occupation</Text>
              <View style={styles.optionRowWrap}>
                {teacherOptions.map((option) => (
                  <OptionButton key={option} label={option} selected={teacherGradeOrOccupation === option} onPress={() => setTeacherGradeOrOccupation(option)} />
                ))}
              </View>
              {teacherGradeOrOccupation === 'Other' && (
                <TextInput placeholder="Please explain" value={teacherOtherExplanation} onChangeText={setTeacherOtherExplanation} style={styles.input} />
              )}
            </>
          )}
        </>
      )}

      <TouchableOpacity style={styles.primaryButton} onPress={handlePrimary} disabled={isBusy}>
        {isBusy ? <ActivityIndicator color="#fff" /> : <Text style={styles.primaryButtonText}>{isSignUp ? 'Create Account' : 'Log In'}</Text>}
      </TouchableOpacity>

      {!isSignUp && (
        <TouchableOpacity style={styles.secondaryButton} onPress={handleReset}>
          <Text style={styles.secondaryButtonText}>Forgot password?</Text>
        </TouchableOpacity>
      )}

      <TouchableOpacity style={styles.ghostButton} onPress={() => setIsSignUp((v) => !v)}>
        <Text style={styles.ghostButtonText}>{isSignUp ? 'I already have an account' : 'Create a new account'}</Text>
      </TouchableOpacity>
    </ScrollView>
  );
}

function OptionButton({ label, selected, onPress }) {
  return (
    <TouchableOpacity style={[styles.optionButton, selected && styles.optionButtonSelected]} onPress={onPress}>
      <Text style={[styles.optionButtonText, selected && styles.optionButtonTextSelected]}>{label}</Text>
    </TouchableOpacity>
  );
}

const styles = StyleSheet.create({
  container: {
    flexGrow: 1,
    padding: 20,
    justifyContent: 'center',
    backgroundColor: '#fff',
  },
  title: {
    fontSize: 24,
    fontWeight: '700',
    marginBottom: 4,
    textAlign: 'center',
  },
  subtitle: {
    fontSize: 14,
    color: '#6b7280',
    marginBottom: 16,
    textAlign: 'center',
  },
  input: {
    borderWidth: 1,
    borderColor: '#d1d5db',
    padding: 12,
    marginBottom: 10,
    borderRadius: 8,
  },
  sectionTitle: {
    fontWeight: '600',
    marginTop: 6,
    marginBottom: 8,
  },
  optionRow: {
    flexDirection: 'row',
    gap: 8,
    marginBottom: 8,
  },
  optionRowWrap: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
    marginBottom: 8,
  },
  optionButton: {
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 999,
    borderWidth: 1,
    borderColor: '#d1d5db',
    marginRight: 8,
    marginBottom: 8,
  },
  optionButtonSelected: {
    backgroundColor: '#2563eb',
    borderColor: '#2563eb',
  },
  optionButtonText: {
    color: '#374151',
  },
  optionButtonTextSelected: {
    color: '#fff',
  },
  primaryButton: {
    backgroundColor: '#2563eb',
    paddingVertical: 12,
    borderRadius: 8,
    alignItems: 'center',
    marginTop: 8,
  },
  primaryButtonText: {
    color: '#fff',
    fontWeight: '700',
  },
  secondaryButton: {
    alignItems: 'center',
    paddingVertical: 10,
  },
  secondaryButtonText: {
    color: '#2563eb',
    fontWeight: '600',
  },
  ghostButton: {
    alignItems: 'center',
    marginTop: 8,
  },
  ghostButtonText: {
    color: '#4b5563',
  },
});
