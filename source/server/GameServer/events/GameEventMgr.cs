using System;
using System.Collections.Generic;
using System.Reflection;
using System.Linq;
using System.Threading;
using DOL.Logging;

namespace DOL.Events
{
    /// <summary>
    /// Manages per-object and global event handlers.
    /// </summary>
    public class GameEventMgr
    {
        private static readonly Logger log = LoggerManager.Create(MethodBase.GetCurrentMethod().DeclaringType);
        private static GameEventMgr _soleInstance = new();

        private readonly Dictionary<object, DOLEventHandlerCollection> _gameObjectEventCollections = new();
        private readonly DOLEventHandlerCollection _globalHandlerCollection = new();
        private readonly ReaderWriterLockSlim _lock = new(LockRecursionPolicy.SupportsRecursion);

        private static DOLEventHandlerCollection GlobalHandlerCollection => _soleInstance._globalHandlerCollection;
        private static Dictionary<object, DOLEventHandlerCollection> GameObjectEventCollections => _soleInstance._gameObjectEventCollections;
        private static ReaderWriterLockSlim Lock => _soleInstance._lock;

        public static int NumGlobalHandlers => GlobalHandlerCollection.Count;

        public static int NumObjectHandlers
        {
            get
            {
                int numHandlers = 0;
                Lock.EnterReadLock();

                try
                {
                    foreach (DOLEventHandlerCollection col in GameObjectEventCollections.Values)
                        numHandlers += col.Count;
                }
                finally
                {
                    Lock.ExitReadLock();
                }

                return numHandlers;
            }
        }

        /// <summary>
        /// Memory diagnostics: objects with handlers, those the predicate calls detached (no longer in the world), and
        /// handlers anywhere whose target (or closure) holds a detached object; a handler left on a live owner keeps
        /// a released pet alive for good.
        /// </summary>
        public static (int Objects, int DetachedObjects, int DetachedTargets, string TargetTypes) Census(Func<object, bool> detached)
        {
            var types = new Dictionary<string, int>();
            int objects, detachedObjects = 0, detachedTargets = 0;
            List<DOLEventHandler> handlers = new();
            Lock.EnterReadLock();
            try
            {
                objects = GameObjectEventCollections.Count;
                foreach (var (owner, collection) in GameObjectEventCollections)
                {
                    if (detached(owner)) detachedObjects++;
                    handlers.AddRange(collection.AllHandlers());
                }
            }
            finally
            {
                Lock.ExitReadLock();
            }
            handlers.AddRange(GlobalHandlerCollection.AllHandlers());
            foreach (DOLEventHandler handler in handlers)
            {
                object target = handler.Target;
                if (target == null) continue;
                object held = detached(target) ? target : null;
                if (held == null && target.GetType().Name.Contains("DisplayClass", StringComparison.Ordinal))
                    foreach (FieldInfo field in target.GetType().GetFields(BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic))
                        if (field.GetValue(target) is { } value && detached(value)) { held = value; break; }
                if (held == null) continue;
                detachedTargets++;
                string key = $"{handler.Method.DeclaringType?.Name}.{handler.Method.Name}";
                types[key] = types.GetValueOrDefault(key) + 1;
            }
            return (objects, detachedObjects, detachedTargets,
                string.Join(",", types.OrderByDescending(p => p.Value).Take(6).Select(p => $"{p.Key}:{p.Value}")));
        }

        public static void LoadTestDouble(GameEventMgr testDouble)
        {
            _soleInstance = testDouble;
        }

        public static void RegisterGlobalEvents(Assembly asm, Type attribute, DOLEvent e)
        {
            ArgumentNullException.ThrowIfNull(asm);
            ArgumentNullException.ThrowIfNull(attribute);
            ArgumentNullException.ThrowIfNull(e);

            foreach (Type type in asm.GetTypes())
            {
                if (!type.IsClass)
                    continue;

                foreach (MethodInfo mInfo in type.GetMethods(BindingFlags.Public | BindingFlags.Static))
                {
                    object[] myAttribs = mInfo.GetCustomAttributes(attribute, false);

                    if (myAttribs.Length != 0)
                    {
                        try
                        {
                            GlobalHandlerCollection.AddHandler(e, (DOLEventHandler) Delegate.CreateDelegate(typeof(DOLEventHandler), mInfo));
                        }
                        catch (Exception ex)
                        {
                            if (log.IsErrorEnabled)
                                log.Error($"Error registering global event. Method: {type.FullName}.{mInfo.Name}", ex);
                        }
                    }
                }
            }
        }

        public static void AddHandler(DOLEvent e, DOLEventHandler del)
        {
            AddHandler(e, del, false);
        }

        public static void AddHandlerUnique(DOLEvent e, DOLEventHandler del)
        {
            AddHandler(e, del, true);
        }

        public static void AddHandlerUnique(object obj, DOLEvent e, DOLEventHandler del)
        {
            AddHandler(obj, e, del, true);
        }

        private static void AddHandler(DOLEvent e, DOLEventHandler del, bool unique)
        {
            ArgumentNullException.ThrowIfNull(e);
            ArgumentNullException.ThrowIfNull(del);

            if (unique)
                GlobalHandlerCollection.AddHandlerUnique(e, del);
            else
                GlobalHandlerCollection.AddHandler(e, del);
        }

        public static void AddHandler(object obj, DOLEvent e, DOLEventHandler del)
        {
            AddHandler(obj, e, del, false);
        }

        private static void AddHandler(object obj, DOLEvent e, DOLEventHandler del, bool unique)
        {
            ArgumentNullException.ThrowIfNull(obj);
            ArgumentNullException.ThrowIfNull(e);
            ArgumentNullException.ThrowIfNull(del);

            if (!e.IsValidFor(obj))
                throw new ArgumentException("Object is not valid for this event type", nameof(obj));

            Lock.EnterUpgradeableReadLock();

            try
            {
                if (!GameObjectEventCollections.TryGetValue(obj, out DOLEventHandlerCollection col))
                {
                    col = new DOLEventHandlerCollection();
                    Lock.EnterWriteLock();

                    try
                    {
                        GameObjectEventCollections.Add(obj, col);
                    }
                    finally
                    {
                        Lock.ExitWriteLock();
                    }
                }

                if (unique)
                    col.AddHandlerUnique(e, del);
                else
                    col.AddHandler(e, del);
            }
            finally
            {
                Lock.ExitUpgradeableReadLock();
            }
        }

        public static void RemoveHandler(DOLEvent e, DOLEventHandler del)
        {
            ArgumentNullException.ThrowIfNull(e);
            ArgumentNullException.ThrowIfNull(del);

            GlobalHandlerCollection.RemoveHandler(e, del);
        }

        public static void RemoveHandler(object obj, DOLEvent e, DOLEventHandler del)
        {
            ArgumentNullException.ThrowIfNull(obj);
            ArgumentNullException.ThrowIfNull(e);
            ArgumentNullException.ThrowIfNull(del);

            DOLEventHandlerCollection col = null;
            Lock.EnterReadLock();

            try
            {
                GameObjectEventCollections.TryGetValue(obj, out col);
            }
            finally
            {
                Lock.ExitReadLock();
            }

            col?.RemoveHandler(e, del);
        }

        public static void RemoveAllHandlersForObject(object obj)
        {
            ArgumentNullException.ThrowIfNull(obj);

            Lock.EnterWriteLock();

            try
            {
                GameObjectEventCollections.Remove(obj);
            }
            finally
            {
                Lock.ExitWriteLock();
            }
        }

        public static void RemoveAllHandlers()
        {
            Lock.EnterWriteLock();

            try
            {
                GameObjectEventCollections.Clear();
            }
            finally
            {
                Lock.ExitWriteLock();
            }

            GlobalHandlerCollection.RemoveAllHandlers();
        }

        public static void Notify(DOLEvent e)
        {
            Notify(e, null, null);
        }

        public static void Notify(DOLEvent e, object sender)
        {
            Notify(e, sender, null);
        }

        public static void Notify(DOLEvent e, EventArgs args)
        {
            Notify(e, null, args);
        }

        public static void Notify(DOLEvent e, object sender, EventArgs eArgs)
        {
            ArgumentNullException.ThrowIfNull(e);

            ECS.Debug.Diagnostics.BeginGameEventMgrNotify();

            if (sender != null)
            {
                DOLEventHandlerCollection col;
                Lock.EnterReadLock();

                try
                {
                    GameObjectEventCollections.TryGetValue(sender, out col);
                }
                finally
                {
                    Lock.ExitReadLock();
                }

                col?.Notify(e, sender, eArgs);
            }

            GlobalHandlerCollection.Notify(e, sender, eArgs);
            ECS.Debug.Diagnostics.EndGameEventMgrNotify(e);
        }
    }
}
