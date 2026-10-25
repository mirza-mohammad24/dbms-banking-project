import { BrowserRouter, Navigate, Route, Routes } from "react-router-dom";
import Login from "./pages/Login";
import { lazy, Suspense } from "react";
import { useSession } from "./lib/session";

const CustomerDashboard = lazy(() => import("./pages/CustomerDashboard"));
const AdminDashboard = lazy(() => import("./pages/AdminDashboard"));

function ProtectedRoute({ role, children }) {
  const user = useSession();
  if (!user) return <Navigate to="/" replace />;
  if (user.role !== role)
    return (
      <Navigate
        to={user.role === "Admin" ? "/admin/dashboard" : "/customer/dashboard"}
        replace
      />
    );
  return children;
}

export default function App() {
  const user = useSession();
  return (
    <BrowserRouter>
      <Suspense
        fallback={
          <div className="grid min-h-screen place-items-center bg-slate-50 dark:bg-slate-950 text-sm text-slate-500 dark:text-slate-400">
            Opening your workspace…
          </div>
        }
      >
        <Routes>
          <Route path="/" element={<Login />} />
          <Route
            path="/customer/dashboard"
            element={
              <ProtectedRoute role="Customer">
                <CustomerDashboard key={user?.id} />
              </ProtectedRoute>
            }
          />
          <Route
            path="/admin/dashboard"
            element={
              <ProtectedRoute role="Admin">
                <AdminDashboard key={user?.id} />
              </ProtectedRoute>
            }
          />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </Suspense>
    </BrowserRouter>
  );
}
