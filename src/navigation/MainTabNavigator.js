import React from 'react';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { Ionicons } from '@expo/vector-icons';
import StudentSubject from '../screens/StudentSubject';
import TeacherSubject from '../screens/TeacherSubject';
import ChatHome from '../screens/ChatHome';
import More from '../screens/More';
import { useAuthState } from '../utils/useAuthState';

const Tab = createBottomTabNavigator();

export default function MainTabNavigator() {
  const { appUser } = useAuthState();
  const isTeacher = appUser?.role === 'teacher';

  return (
    <Tab.Navigator screenOptions={({ route }) => ({
      headerShown: false,
      tabBarIcon: ({ color, size }) => {
        let name = 'ios-home';
        if (route.name === 'Music') name = 'musical-notes';
        if (route.name === 'Academic') name = 'book';
        if (route.name === 'Chat') name = 'chatbubbles';
        if (route.name === 'More') name = 'ellipsis-horizontal-circle';
        return <Ionicons name={name} size={size} color={color} />;
      }
    })}>
      <Tab.Screen name="Music" component={isTeacher ? TeacherSubject : StudentSubject} />
      <Tab.Screen name="Academic" component={isTeacher ? TeacherSubject : StudentSubject} />
      <Tab.Screen name="Chat" component={ChatHome} />
      <Tab.Screen name="More" component={More} />
    </Tab.Navigator>
  );
}
