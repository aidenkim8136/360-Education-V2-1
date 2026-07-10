import { initializeApp } from 'firebase/app';
import { getAuth } from 'firebase/auth';
import { getFirestore } from 'firebase/firestore';

const firebaseConfig = {
  apiKey: "AIzaSyCG8aXpetsA8FicoinFev93-5eAgQpirj4",
  authDomain: "teachingapp-35b80.firebaseapp.com",
  projectId: "teachingapp-35b80",
  storageBucket: "teachingapp-35b80.firebasestorage.app",
  messagingSenderId: "709926457791",
  appId: "1:709926457791:ios:645f6a600ef184d50ad10a",
  databaseURL: "https://teachingapp-35b80-default-rtdb.firebaseio.com"
};

let app;
let auth;
let db;

export function initializeFirebase() {
  try {
    if (!app) {
      app = initializeApp(firebaseConfig);
      auth = getAuth(app);
      db = getFirestore(app);
    }
  } catch (e) {
    console.warn('Firebase init error', e);
  }
}

export function getFirebaseAuth() {
  if (!auth) {
    initializeFirebase();
  }
  return auth;
}

export function getFirestoreDb() {
  if (!db) {
    initializeFirebase();
  }
  return db;
}
