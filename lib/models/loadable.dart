enum LoadStatus { initial, loading, refreshing, success, error }

class Loadable<T> {
  const Loadable._({required this.status, this.data, this.error});

  const Loadable.initial() : this._(status: LoadStatus.initial);

  const Loadable.loading({T? data})
    : this._(status: LoadStatus.loading, data: data);

  const Loadable.refreshing(T data)
    : this._(status: LoadStatus.refreshing, data: data);

  const Loadable.success(T data)
    : this._(status: LoadStatus.success, data: data);

  const Loadable.error(String error, {T? data})
    : this._(status: LoadStatus.error, data: data, error: error);

  final LoadStatus status;
  final T? data;
  final String? error;

  bool get isInitial => status == LoadStatus.initial;
  bool get isLoading => status == LoadStatus.loading;
  bool get isRefreshing => status == LoadStatus.refreshing;
  bool get isSuccess => status == LoadStatus.success;
  bool get isError => status == LoadStatus.error;
  bool get hasData => data != null;
  bool get shouldShowInitialLoading => (isInitial || isLoading) && data == null;
}
