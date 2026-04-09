using UnityEngine;

public class ActionBarView : MonoBehaviour
{
    public void OnAutoArrangeClicked()
    {
        Debug.Log("Auto arrange clicked");
    }

    public void OnUndoClicked()
    {
        if (!GameSession.Instance.Undo())
            Debug.Log("Undo rejected by C++");
    }

    public void OnSubmitClicked()
    {
        if (!GameSession.Instance.SubmitMyHand())
            Debug.Log("Submit rejected by C++");
    }
}
