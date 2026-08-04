# Employee Capability Audit & Screen Redesign Plan

## Overview

This audit cross-references all backend endpoints across `services/user-service`, `services/auth-service`, `services/notification-service`, and `services/chat-service` that accept employee-role (`RoleEmployee`) JWT authentication or employee token authorization. It identifies current frontend provider wiring and surfaces any UI reachability gaps prior to the Employee screen redesign.

---

## Backend Capability Matrix

| Service | Endpoint | Method | Backend Function | Handler Role Gating | Frontend Wiring Status | Screen Exposing Capability |
|---|---|---|---|---|---|---|
| `user-service` | `/users/jobs/get` | `GET` | List assigned jobs for employee | `owner`, `employee`, `user`, `customer` | **Wired** (`EmployeeJobsProvider.fetchAssignedJobs`) | `EmployeeJobsScreen` |
| `user-service` | `/users/jobs/complete` | `POST` | Mark assigned active job completed & process COD | `owner`, `employee` | **Wired** (`EmployeeJobsProvider.completeJob`) | `EmployeeJobsScreen` |
| `user-service` | `/users/jobs/cancel` | `POST` | Cancel pending/active job | `owner`, `employee`, `user`, `customer` | **Wired in Provider** | `CustomerJobsScreen` / `HomeScreen` |
| `user-service` | `/users/jobs/location` | `POST` | Update live employee GPS coordinates & broadcast | `employee` | **Wired** (`EmployeeLocationProvider.startTracking`) | `EmployeeJobsScreen` |
| `auth-service` | `/auth/employee/action` | `POST` | Log worker service event into audit trail | `employee` | **Wired** (`EmployeeJobsProvider.simulateAction`) | `EmployeeJobsScreen` |
| `auth-service` | `/auth/kye/upload` | `POST` | Upload KYE verification docs (`id_front`, `id_back`, `selfie`) | `employee` | **Wired in Screen** | **UNREACHABLE GAP** (No button on `EmployeeJobsScreen`) |
| `chat-service` | `/chat/ws` | `GET` (WS) | Join real-time WebSocket job channel (`job:<job_id>`) | Channel participant check (`owner`, `employee`, `user`) | **Wired** (`ChatProvider.connect`) | **UNREACHABLE GAP** (No chat button on employee job cards) |
| `chat-service` | `/chat/history` | `GET` | Fetch job channel message history | Channel participant check | **Wired** (`ChatProvider.fetchHistory`) | **UNREACHABLE GAP** (No chat button on employee job cards) |
| `chat-service` | `/chat/tickets` | `POST` | Open complaint/support ticket | `owner`, `employee`, `user` | **Wired** (`ChatProvider.createTicket`) | `JobStatusScreen` / `SettingsScreen` |
| `auth-service` | `/auth/user` | `GET`/`PATCH` | Read profile & update self-service fields | Authenticated User (`owner`, `employee`, `user`) | **Wired** (`AuthProvider.updateProfile`) | `SettingsScreen` |
| `notification-service` | `/notifications/stream` | `GET` (SSE) | Stream real-time notifications for tenant | Tenant match | **Wired** (`NotificationsProvider`) | AppBar Bell across screens |

---

## Identified Reachability Gaps

1. **Job Channel Real-time Chat (`GET /chat/ws` & `GET /chat/history`)**:
   - `ChatProvider` and `ChatScreen` support job channel messaging, but `EmployeeJobsScreen` job cards lacked a "Chat" button. Employees could not open the chat view for active/pending jobs.
   - **Resolution in Redesign**: Add a "Chat" button (`key: Key('employee_chat_button_<job_id>')`) on job cards for assigned jobs in `EmployeeJobsScreen`.

2. **KYE Document Verification Upload (`POST /auth/kye/upload`)**:
   - `KycDocumentUploadScreen` supports employee KYE document uploads (`id_front`, `id_back`, `selfie`), but there was no entry point on `EmployeeJobsScreen` to access it.
   - **Resolution in Redesign**: Add a "Verification Documents" button (`key: Key('employee_verification_button')`) in the AppBar / Header of `EmployeeJobsScreen`.

---

## Layout Decision & Architecture

- **Single-Screen Sectional Dashboard Architecture**:
  - Based on this audit, the Employee role has **one primary operational focus**: managing assigned jobs and executing field delivery workflow (location tracking, action logging, job completion, and customer chat).
  - Rather than splitting into multi-tab navigation, the Employee UI uses a clean, single-screen sectional dashboard (`EmployeeJobsScreen`) with:
    1. **AppBar**: Quick access to Refresh, KYE Verification Documents, Notifications Bell, and Settings.
    2. **Status Banner**: Live GPS location sharing indicator when an active job exists.
    3. **Action Simulator Section**: Quick logging of service events into the tenant audit trail.
    4. **Assigned Jobs Roster**: Complete job cards featuring status badges, destination coordinates, customer ID, payment method, escrow info, **Real-time Chat Button**, and **Job Completion Button**.
