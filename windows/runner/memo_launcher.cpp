#include <windows.h>
#include <taskschd.h>
#include <wrl/client.h>

#include <cwchar>

namespace {

HRESULT RequestIndependentLaunch() {
  Microsoft::WRL::ComPtr<ITaskService> service;
  HRESULT result = CoCreateInstance(CLSID_TaskScheduler, nullptr,
                                    CLSCTX_INPROC_SERVER,
                                    IID_PPV_ARGS(service.GetAddressOf()));
  if (FAILED(result)) {
    return result;
  }

  VARIANT empty{};
  result = service->Connect(empty, empty, empty, empty);
  if (FAILED(result)) {
    return result;
  }

  BSTR folder_path = SysAllocString(L"\\");
  if (!folder_path) {
    return E_OUTOFMEMORY;
  }
  Microsoft::WRL::ComPtr<ITaskFolder> folder;
  result = service->GetFolder(folder_path, folder.GetAddressOf());
  SysFreeString(folder_path);
  if (FAILED(result)) {
    return result;
  }

  BSTR task_name = SysAllocString(L"DesktopMemo-IndependentLaunch");
  if (!task_name) {
    return E_OUTOFMEMORY;
  }
  Microsoft::WRL::ComPtr<IRegisteredTask> task;
  result = folder->GetTask(task_name, task.GetAddressOf());
  SysFreeString(task_name);
  if (FAILED(result)) {
    return result;
  }

  // Keep the task's existing IgnoreNew policy and independent process lifetime.
  Microsoft::WRL::ComPtr<IRunningTask> running_task;
  result = task->Run(empty, running_task.GetAddressOf());
  // A second click while the note is open is an intentional no-op.
  return result == SCHED_E_ALREADY_RUNNING ? S_OK : result;
}

int ShowLaunchError(HRESULT result) {
  wchar_t message[160];
  swprintf_s(message,
             L"无法启动桌面便利贴。\n请检查独立启动任务是否可用。"
             L"\n错误代码：0x%08lX",
             static_cast<unsigned long>(result));
  MessageBoxW(nullptr, message, L"桌面便利贴", MB_OK | MB_ICONERROR);
  return 1;
}

}  // namespace

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
  HRESULT result = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  if (FAILED(result)) {
    return ShowLaunchError(result);
  }

  result = CoInitializeSecurity(nullptr, -1, nullptr, nullptr,
                                RPC_C_AUTHN_LEVEL_PKT_PRIVACY,
                                RPC_C_IMP_LEVEL_IMPERSONATE, nullptr, EOAC_NONE,
                                nullptr);
  if (SUCCEEDED(result)) {
    result = RequestIndependentLaunch();
  }
  CoUninitialize();
  return FAILED(result) ? ShowLaunchError(result) : 0;
}
